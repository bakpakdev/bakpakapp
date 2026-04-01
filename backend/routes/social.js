const express = require('express');
const { PrismaClient } = require('@prisma/client');
const { protect } = require('../middleware/auth');

const router = express.Router();
const prisma = new PrismaClient();

// @route   POST /api/social/follow/:userId
// @desc    Follow a user
// @access  Private
router.post('/follow/:userId', protect, async (req, res) => {
  try {
    if (req.user.id === req.params.userId) {
      return res.status(400).json({ message: 'Cannot follow yourself' });
    }

    const follow = await prisma.follow.create({
      data: {
        followerId: req.user.id,
        followingId: req.params.userId,
      },
    });

    res.json(follow);
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(400).json({ message: 'Already following this user' });
    }
    console.error('Follow error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   DELETE /api/social/follow/:userId
// @desc    Unfollow a user
// @access  Private
router.delete('/follow/:userId', protect, async (req, res) => {
  try {
    await prisma.follow.deleteMany({
      where: {
        followerId: req.user.id,
        followingId: req.params.userId,
      },
    });

    res.json({ message: 'Unfollowed successfully' });
  } catch (error) {
    console.error('Unfollow error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/social/following/:userId
// @desc    Get users that a user is following
// @access  Public
router.get('/following/:userId', async (req, res) => {
  try {
    const following = await prisma.follow.findMany({
      where: { followerId: req.params.userId },
      include: {
        following: {
          select: {
            id: true,
            username: true,
            avatar: true,
            shopName: true,
          },
        },
      },
    });

    res.json(following.map((f) => f.following));
  } catch (error) {
    console.error('Get following error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/social/followers/:userId
// @desc    Get users that follow a user
// @access  Public
router.get('/followers/:userId', async (req, res) => {
  try {
    const followers = await prisma.follow.findMany({
      where: { followingId: req.params.userId },
      include: {
        follower: {
          select: {
            id: true,
            username: true,
            avatar: true,
            shopName: true,
          },
        },
      },
    });

    res.json(followers.map((f) => f.follower));
  } catch (error) {
    console.error('Get followers error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   POST /api/social/like/:productId
// @desc    Like a product
// @access  Private
router.post('/like/:productId', protect, async (req, res) => {
  try {
    const like = await prisma.like.create({
      data: {
        userId: req.user.id,
        productId: req.params.productId,
      },
    });

    res.json(like);
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(400).json({ message: 'Already liked this product' });
    }
    console.error('Like error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   DELETE /api/social/like/:productId
// @desc    Unlike a product
// @access  Private
router.delete('/like/:productId', protect, async (req, res) => {
  try {
    await prisma.like.deleteMany({
      where: {
        userId: req.user.id,
        productId: req.params.productId,
      },
    });

    res.json({ message: 'Unliked successfully' });
  } catch (error) {
    console.error('Unlike error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/social/likes/:productId
// @desc    Check if user liked a product
// @access  Private
router.get('/likes/:productId', protect, async (req, res) => {
  try {
    const like = await prisma.like.findUnique({
      where: {
        userId_productId: {
          userId: req.user.id,
          productId: req.params.productId,
        },
      },
    });

    res.json({ liked: !!like });
  } catch (error) {
    console.error('Check like error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   POST /api/social/save/:productId
// @desc    Save a product
// @access  Private
router.post('/save/:productId', protect, async (req, res) => {
  try {
    const savedItem = await prisma.savedItem.create({
      data: {
        userId: req.user.id,
        productId: req.params.productId,
      },
    });

    res.json(savedItem);
  } catch (error) {
    if (error.code === 'P2002') {
      return res.status(400).json({ message: 'Already saved this product' });
    }
    console.error('Save error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   DELETE /api/social/save/:productId
// @desc    Unsave a product
// @access  Private
router.delete('/save/:productId', protect, async (req, res) => {
  try {
    await prisma.savedItem.deleteMany({
      where: {
        userId: req.user.id,
        productId: req.params.productId,
      },
    });

    res.json({ message: 'Unsaved successfully' });
  } catch (error) {
    console.error('Unsave error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/social/saved
// @desc    Get user's saved items
// @access  Private
router.get('/saved', protect, async (req, res) => {
  try {
    const savedItems = await prisma.savedItem.findMany({
      where: { userId: req.user.id },
      include: {
        product: {
          include: {
            images: true,
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
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    res.json(savedItems.map((item) => item.product));
  } catch (error) {
    console.error('Get saved items error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/social/liked
// @desc    Get user's liked items
// @access  Private
router.get('/liked', protect, async (req, res) => {
  try {
    const likedItems = await prisma.like.findMany({
      where: { userId: req.user.id },
      include: {
        product: {
          include: {
            images: true,
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
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    res.json(likedItems.map((item) => item.product));
  } catch (error) {
    console.error('Get liked items error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;

