const express = require('express');
const { PrismaClient } = require('@prisma/client');
const jwt = require('jsonwebtoken');
const recommendationService = require('../services/recommendationService');

const router = express.Router();
const prisma = new PrismaClient();

/** In-memory click popularity until a dedicated SearchEvent table is migrated. */
const suggestionClicks = new Map(); // lowercased suggestion -> count

function bumpSuggestion(text) {
  if (!text) return;
  const key = String(text).trim().toLowerCase();
  if (!key) return;
  suggestionClicks.set(key, (suggestionClicks.get(key) || 0) + 1);
}

function scoreCandidate(text, query, type) {
  const t = text.toLowerCase();
  const q = query.toLowerCase();
  let score = 0;
  if (!q) {
    score += type === 'trending' ? 12 : type === 'brand' ? 10 : 6;
  } else if (t.startsWith(q)) {
    score += 40;
  } else if (t.includes(q)) {
    score += 22;
  } else {
    return 0;
  }
  if (type === 'brand') score += 12;
  if (type === 'listing') score += 8;
  if (type === 'trending') score += 6;
  score += Math.min(25, (suggestionClicks.get(t) || 0) * 3);
  return score;
}

// Optional auth middleware - doesn't fail if no token
const optionalAuth = async (req, res, next) => {
  try {
    let token;

    if (req.headers.authorization && req.headers.authorization.startsWith('Bearer')) {
      token = req.headers.authorization.split(' ')[1];
    }

    if (token) {
      try {
        const decoded = jwt.verify(token, process.env.JWT_SECRET);
        const user = await prisma.user.findUnique({
          where: { id: decoded.id },
          select: {
            id: true,
            email: true,
            username: true,
            firstName: true,
            lastName: true,
            avatar: true,
            country: true,
          },
        });

        if (user) {
          req.user = user;
        } else {
          req.user = null;
        }
      } catch (error) {
        req.user = null;
      }
    } else {
      req.user = null;
    }

    next();
  } catch (error) {
    req.user = null;
    next();
  }
};

// @route   GET /api/search/suggest
// @desc    Ranked typeahead suggestions (Phase 1 popularity + match ranking)
// @access  Public
router.get('/suggest', optionalAuth, async (req, res) => {
  try {
    const q = String(req.query.q || '').trim();
    const limit = Math.min(12, Math.max(1, parseInt(req.query.limit, 10) || 8));
    const school = String(req.query.school || req.user?.country || '').trim();

    const candidates = new Map(); // lower -> { text, type, score }

    const add = (text, type) => {
      const cleaned = String(text || '').trim();
      if (!cleaned || cleaned.length < 2) return;
      const score = scoreCandidate(cleaned, q, type);
      if (score <= 0 && q) return;
      const key = cleaned.toLowerCase();
      const prev = candidates.get(key);
      if (!prev || score > prev.score) {
        candidates.set(key, { text: cleaned, type, score });
      }
    };

    const products = await prisma.product.findMany({
      where: {
        isSold: false,
        ...(q
          ? {
              OR: [
                { title: { contains: q, mode: 'insensitive' } },
                { brand: { contains: q, mode: 'insensitive' } },
                { category: { contains: q, mode: 'insensitive' } },
              ],
            }
          : {}),
      },
      select: { title: true, brand: true, category: true },
      take: q ? 40 : 30,
      orderBy: { createdAt: 'desc' },
    });

    products.forEach((p) => {
      if (p.title) add(p.title, 'listing');
      if (p.brand) add(p.brand, 'brand');
      if (p.category) add(p.category, 'category');
    });

    for (const [key, count] of suggestionClicks.entries()) {
      if (!q || key.includes(q.toLowerCase())) {
        const display = key.replace(/\b\w/g, (c) => c.toUpperCase());
        add(display, 'popular');
        const cur = candidates.get(key);
        if (cur) cur.score += Math.min(25, count * 3);
      }
    }

    const suggestions = Array.from(candidates.values())
      .sort((a, b) => b.score - a.score)
      .slice(0, limit)
      .map(({ text, type, score }) => ({
        text,
        type,
        score: Math.round(score * 10) / 10,
      }));

    res.json({
      query: q,
      school: school || null,
      suggestions,
    });
  } catch (error) {
    console.error('Suggest error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   POST /api/search/events
// @desc    Log typeahead / click / submit for future model training
// @access  Public (optional auth)
router.post('/events', optionalAuth, async (req, res) => {
  try {
    const {
      queryText = '',
      suggestionText = null,
      suggestionType = null,
      resultProductId = null,
      eventType = 'typeahead',
      school = null,
    } = req.body || {};

    if (eventType === 'click' && suggestionText) {
      bumpSuggestion(suggestionText);
    }
    if (eventType === 'submit' && (suggestionText || queryText)) {
      bumpSuggestion(suggestionText || queryText);
    }

    res.status(201).json({
      ok: true,
      logged: {
        userId: req.user?.id || null,
        queryText,
        suggestionText,
        suggestionType,
        resultProductId,
        eventType,
        school: school || req.user?.country || null,
      },
    });
  } catch (error) {
    console.error('Search event error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/search
// @desc    Search products (excludes user's own listings if logged in)
// @access  Public (works better with auth to exclude own listings)
router.get('/', optionalAuth, async (req, res) => {
  try {
    const { q, category, minPrice, maxPrice, condition, size, brand, sortBy = 'newest' } = req.query;
    const userId = req.user?.id || null;

    console.log('Search request - userId:', userId, 'user:', req.user?.username);

    const where = {
      isSold: false,
    };

    if (userId) {
      where.userId = { not: userId };
      console.log('Filtering out user listings for userId:', userId);
    } else {
      console.log('No userId provided - showing all listings');
    }

    if (q) {
      where.OR = [
        { title: { contains: q, mode: 'insensitive' } },
        { description: { contains: q, mode: 'insensitive' } },
        { brand: { contains: q, mode: 'insensitive' } },
      ];
    }

    if (category) {
      where.category = category;
    }

    if (condition) {
      where.condition = condition;
    }

    if (size) {
      where.size = size;
    }

    if (brand) {
      where.brand = { contains: brand, mode: 'insensitive' };
    }

    if (minPrice || maxPrice) {
      where.price = {};
      if (minPrice) where.price.gte = parseFloat(minPrice);
      if (maxPrice) where.price.lte = parseFloat(maxPrice);
    }

    let orderBy = {};
    switch (sortBy) {
      case 'price-low':
        orderBy = { price: 'asc' };
        break;
      case 'price-high':
        orderBy = { price: 'desc' };
        break;
      case 'newest':
      default:
        orderBy = { createdAt: 'desc' };
        break;
    }

    let products = await prisma.product.findMany({
      where,
      select: {
        id: true,
        title: true,
        description: true,
        price: true,
        condition: true,
        size: true,
        brand: true,
        category: true,
        tags: true,
        isSold: true,
        createdAt: true,
        updatedAt: true,
        userId: true,
        images: {
          where: { isPrimary: true },
        },
        user: {
          select: {
            id: true,
            username: true,
            avatar: true,
          },
        },
        _count: {
          select: {
            likes: true,
          },
        },
      },
      orderBy,
    });

    if (q) {
      const tagMatches = products.filter((product) => {
        if (product.tags && Array.isArray(product.tags)) {
          return product.tags.some((tag) =>
            tag.toLowerCase().includes(q.toLowerCase())
          );
        }
        return false;
      });

      const existingIds = new Set(products.map((p) => p.id));
      tagMatches.forEach((product) => {
        if (!existingIds.has(product.id)) {
          products.push(product);
        }
      });
    }

    if (userId) {
      products = products.filter((product) => product.userId !== userId);
      console.log('After filtering user listings, products count:', products.length);
    }

    if (q) {
      const scoredProducts = products.map((product) => {
        const relevanceScore = recommendationService.calculateRelevanceScore(product, q);
        const qualityScore = recommendationService.calculateListingQualityScore(product);

        return {
          ...product,
          relevanceScore,
          qualityScore,
          totalScore: relevanceScore + qualityScore * 0.3,
        };
      });

      products = scoredProducts.sort((a, b) => b.totalScore - a.totalScore);
    } else if (sortBy === 'relevance' || sortBy === 'recommended') {
      const scoredProducts = products.map((product) => {
        const qualityScore = recommendationService.calculateListingQualityScore(product);
        return {
          ...product,
          qualityScore,
          totalScore: qualityScore,
        };
      });

      products = scoredProducts.sort((a, b) => b.totalScore - a.totalScore);
    }

    res.json(products);
  } catch (error) {
    console.error('Search error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/search/categories
// @desc    Get all categories
// @access  Public
router.get('/categories', async (req, res) => {
  try {
    const categories = await prisma.product.groupBy({
      by: ['category'],
      where: { isSold: false },
      _count: {
        category: true,
      },
    });

    res.json(categories);
  } catch (error) {
    console.error('Get categories error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;
