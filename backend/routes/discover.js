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

// @route   GET /api/discover
// @desc    Get personalized discovery feed (Depop-style recommendations)
// @access  Public (works better with auth for personalization)
router.get('/', optionalAuth, async (req, res) => {
  try {
    const userId = req.user?.id || null;
    const limit = parseInt(req.query.limit) || 20;
    
    // Get personalized recommendations
    // Uses ML-like algorithm to analyze user preferences from:
    // - Liked products
    // - Saved items
    // - Viewed products
    // - Purchase history
    let recommendations = await recommendationService.getPersonalizedRecommendations(userId, limit);
    
    // If no recommendations, fallback to regular products sorted by quality
    if (!recommendations || recommendations.length === 0) {
      const products = await prisma.product.findMany({
        where: {
          isSold: false,
          ...(userId && {
            userId: { not: userId },
          }),
        },
        include: {
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
              views: true,
            },
          },
        },
        take: limit,
        orderBy: {
          createdAt: 'desc',
        },
      });
      
      // Score by quality and engagement
      recommendations = products.map(product => {
        const qualityScore = recommendationService.calculateListingQualityScore(product);
        const engagementScore = (product._count.likes * 2) + (product._count.views * 0.1);
        return {
          ...product,
          recommendationScore: qualityScore + engagementScore,
        };
      }).sort((a, b) => b.recommendationScore - a.recommendationScore);
    }
    
    res.json(recommendations);
  } catch (error) {
    console.error('Discover error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/discover/trending
// @desc    Get trending products based on engagement and quality
// @access  Public
router.get('/trending', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 20;
    
    const products = await prisma.product.findMany({
      where: {
        isSold: false,
      },
      include: {
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
            views: true,
          },
        },
      },
      take: limit * 2,
    });
    
    // Score products by engagement and quality
    const scoredProducts = products.map(product => {
      const qualityScore = recommendationService.calculateListingQualityScore(product);
      const engagementScore = (product._count.likes * 3) + (product._count.views * 0.1);
      const recencyScore = Math.max(0, 100 - (Date.now() - new Date(product.createdAt).getTime()) / (1000 * 60 * 60 * 24)); // Decay over days
      
      const totalScore = (qualityScore * 0.4) + (engagementScore * 0.4) + (recencyScore * 0.2);
      
      return {
        ...product,
        trendingScore: totalScore,
      };
    });
    
    // Sort by score and return top results
    const trending = scoredProducts
      .sort((a, b) => b.trendingScore - a.trendingScore)
      .slice(0, limit);
    
    res.json(trending);
  } catch (error) {
    console.error('Trending error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;

