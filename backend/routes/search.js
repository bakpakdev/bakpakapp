const express = require('express');
const { PrismaClient } = require('@prisma/client');
const jwt = require('jsonwebtoken');
const recommendationService = require('../services/recommendationService');

const router = express.Router();
const prisma = new PrismaClient();

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
          },
        });

        if (user) {
          req.user = user;
        } else {
          req.user = null;
        }
      } catch (error) {
        // Token invalid, continue without user
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
    
    // Exclude user's own listings if logged in (same as discover tab)
    if (userId) {
      where.userId = { not: userId };
      console.log('Filtering out user listings for userId:', userId);
    } else {
      console.log('No userId provided - showing all listings');
    }

    // Text search
    if (q) {
      where.OR = [
        { title: { contains: q, mode: 'insensitive' } },
        { description: { contains: q, mode: 'insensitive' } },
        { brand: { contains: q, mode: 'insensitive' } },
        // Note: Tag search in JSON requires raw SQL for MySQL
        // We'll filter tags in application code after fetching
      ];
    }

    // Filters
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

    // Sort options
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
        userId: true, // Include userId for filtering
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

    // Filter by tags if search query provided (MySQL JSON search)
    if (q) {
      const tagMatches = products.filter((product) => {
        if (product.tags && Array.isArray(product.tags)) {
          return product.tags.some((tag) =>
            tag.toLowerCase().includes(q.toLowerCase())
          );
        }
        return false;
      });
      
      // Merge tag matches with existing results (avoid duplicates)
      const existingIds = new Set(products.map(p => p.id));
      tagMatches.forEach(product => {
        if (!existingIds.has(product.id)) {
          products.push(product);
        }
      });
    }
    
    // Final filter: Remove user's own listings if logged in (in case tag matching added them back)
    if (userId) {
      products = products.filter(product => product.userId !== userId);
      console.log('After filtering user listings, products count:', products.length);
    }

    // Apply relevance scoring if search query provided
    if (q) {
      const scoredProducts = products.map(product => {
        const relevanceScore = recommendationService.calculateRelevanceScore(product, q);
        const qualityScore = recommendationService.calculateListingQualityScore(product);
        
        return {
          ...product,
          relevanceScore,
          qualityScore,
          totalScore: relevanceScore + (qualityScore * 0.3), // Quality boosts relevance
        };
      });
      
      // Sort by relevance score (highest first)
      products = scoredProducts.sort((a, b) => b.totalScore - a.totalScore);
    } else if (sortBy === 'relevance' || sortBy === 'recommended') {
      // If no query but relevance sort requested, use quality score
      const scoredProducts = products.map(product => {
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

