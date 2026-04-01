const express = require('express');
const { PrismaClient } = require('@prisma/client');
const { protect } = require('../middleware/auth');
const multer = require('multer');
const cloudinary = require('cloudinary').v2;

const router = express.Router();
const prisma = new PrismaClient();

// Configure Cloudinary
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET,
});

// Configure Multer for memory storage
const storage = multer.memoryStorage();
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB for avatar
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  },
});

// @route   GET /api/users/:id
// @desc    Get user profile
// @access  Public
router.get('/:id', async (req, res) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.params.id },
      select: {
        id: true,
        username: true,
        firstName: true,
        lastName: true,
        avatar: true,
        bio: true,
        shopName: true,
        dateOfBirth: true,
        country: true,
        isVerified: true,
        createdAt: true,
        _count: {
          select: {
            products: true,
            followers: true,
            following: true,
          },
        },
      },
    });

    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    res.json(user);
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   POST /api/users/:id/avatar
// @desc    Upload user avatar
// @access  Private
router.post('/:id/avatar', protect, upload.single('avatar'), async (req, res) => {
  try {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    if (!req.file) {
      return res.status(400).json({ message: 'No image file provided' });
    }

    // Upload to Cloudinary
    const result = await new Promise((resolve, reject) => {
      cloudinary.uploader
        .upload_stream(
          {
            resource_type: 'image',
            folder: 'thrift-app/avatars',
            width: 400,
            height: 400,
            crop: 'fill',
            gravity: 'face',
          },
          (error, result) => {
            if (error) reject(error);
            else resolve(result);
          }
        )
        .end(req.file.buffer);
    });

    // Update user avatar
    const user = await prisma.user.update({
      where: { id: req.params.id },
      data: {
        avatar: result.secure_url,
      },
      select: {
        id: true,
        email: true,
        username: true,
        firstName: true,
        lastName: true,
        avatar: true,
        bio: true,
        shopName: true,
        dateOfBirth: true,
        country: true,
        isVerified: true,
        createdAt: true,
      },
    });

    // Format dateOfBirth as YYYY-MM-DD string to avoid timezone issues
    if (user.dateOfBirth) {
      const date = new Date(user.dateOfBirth);
      const year = date.getUTCFullYear();
      const month = String(date.getUTCMonth() + 1).padStart(2, '0');
      const day = String(date.getUTCDate()).padStart(2, '0');
      user.dateOfBirth = `${year}-${month}-${day}`;
    }

    res.json(user);
  } catch (error) {
    console.error('Upload avatar error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   PUT /api/users/:id
// @desc    Update user profile
// @access  Private
router.put('/:id', protect, async (req, res) => {
  try {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    const { username, firstName, lastName, bio, shopName, avatar, dateOfBirth, country } = req.body;

    console.log('Update request received:', { username, firstName, lastName, bio, country, dateOfBirth });

    const updateData = {};

    // Update username if provided
    if (username !== undefined && username !== null) {
      const trimmedUsername = username.trim();
      if (trimmedUsername !== req.user.username) {
        // Check if new username is available
        const existingUser = await prisma.user.findUnique({
          where: { username: trimmedUsername },
        });
        if (existingUser) {
          return res.status(400).json({ message: 'Username already taken' });
        }
        updateData.username = trimmedUsername;
      } else {
        // Even if same, update to ensure it's trimmed
        updateData.username = trimmedUsername;
      }
    }

    // Update other fields (including empty strings to clear fields)
    if (firstName !== undefined) updateData.firstName = firstName && firstName.trim() ? firstName.trim() : null;
    if (lastName !== undefined) updateData.lastName = lastName && lastName.trim() ? lastName.trim() : null;
    if (bio !== undefined) updateData.bio = bio && bio.trim() ? bio.trim() : null;
    if (shopName !== undefined) updateData.shopName = shopName && shopName.trim() ? shopName.trim() : null;
    if (avatar !== undefined) updateData.avatar = avatar && avatar.trim() ? avatar.trim() : null;
    if (country !== undefined) updateData.country = country && country.trim() ? country.trim() : null;

    // Handle date of birth - allow null to clear it
    // Store as date string to avoid timezone issues
    if (dateOfBirth !== undefined) {
      if (dateOfBirth && typeof dateOfBirth === 'string' && dateOfBirth.match(/^\d{4}-\d{2}-\d{2}$/)) {
        // If it's already in YYYY-MM-DD format, parse it as a date at midnight UTC to avoid timezone shifts
        const [year, month, day] = dateOfBirth.split('-').map(Number);
        // Create date in UTC to avoid timezone conversion issues
        const date = new Date(Date.UTC(year, month - 1, day, 12, 0, 0)); // Use noon UTC to avoid day shifts
        updateData.dateOfBirth = date;
      } else if (dateOfBirth) {
        // If it's a different format, try to parse it
        updateData.dateOfBirth = new Date(dateOfBirth);
      } else {
        updateData.dateOfBirth = null;
      }
    }

    console.log('Update data:', updateData);

    // Ensure we have at least one field to update
    if (Object.keys(updateData).length === 0) {
      // If nothing to update, just return current user
      const user = await prisma.user.findUnique({
        where: { id: req.params.id },
        select: {
          id: true,
          email: true,
          username: true,
          firstName: true,
          lastName: true,
          avatar: true,
          bio: true,
          shopName: true,
          dateOfBirth: true,
          country: true,
          isVerified: true,
          createdAt: true,
        },
      });
      return res.json(user);
    }

      const user = await prisma.user.update({
        where: { id: req.params.id },
        data: updateData,
        select: {
          id: true,
          email: true,
          username: true,
          firstName: true,
          lastName: true,
          avatar: true,
          bio: true,
          shopName: true,
          dateOfBirth: true,
          country: true,
          isVerified: true,
          createdAt: true,
        },
      });

      // Format dateOfBirth as YYYY-MM-DD string to avoid timezone issues
      if (user.dateOfBirth) {
        const date = new Date(user.dateOfBirth);
        const year = date.getUTCFullYear();
        const month = String(date.getUTCMonth() + 1).padStart(2, '0');
        const day = String(date.getUTCDate()).padStart(2, '0');
        user.dateOfBirth = `${year}-${month}-${day}`;
      }

      console.log('User updated successfully:', user.username);
      res.json(user);
  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   DELETE /api/users/:id
// @desc    Delete user account
// @access  Private
router.delete('/:id', protect, async (req, res) => {
  try {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    // Delete user (cascade will handle related records)
    await prisma.user.delete({
      where: { id: req.params.id },
    });

    res.json({ message: 'Account deleted successfully' });
  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/users/:id/products
// @desc    Get user's products
// @access  Public
router.get('/:id/products', async (req, res) => {
  try {
    const { page = 1, limit = 20 } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);

    const products = await prisma.product.findMany({
      where: {
        userId: req.params.id,
        isSold: false,
      },
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
      orderBy: {
        createdAt: 'desc',
      },
      skip,
      take: parseInt(limit),
    });

    res.json(products);
  } catch (error) {
    console.error('Get user products error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;

