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
  limits: { fileSize: 10 * 1024 * 1024 }, // 10MB
  fileFilter: (req, file, cb) => {
    if (file.mimetype.startsWith('image/')) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  },
});

// @route   GET /api/products
// @desc    Get all products
// @access  Public
router.get('/', async (req, res) => {
  try {
    const { page = 1, limit = 20, category, minPrice, maxPrice, search } = req.query;
    const skip = (parseInt(page) - 1) * parseInt(limit);

    const where = {
      isSold: false,
    };

    if (category) {
      where.category = category;
    }

    if (minPrice || maxPrice) {
      where.price = {};
      if (minPrice) where.price.gte = parseFloat(minPrice);
      if (maxPrice) where.price.lte = parseFloat(maxPrice);
    }

    if (search) {
      where.OR = [
        { title: { contains: search, mode: 'insensitive' } },
        { description: { contains: search, mode: 'insensitive' } },
        { brand: { contains: search, mode: 'insensitive' } },
        { tags: { has: search } },
      ];
    }

    const products = await prisma.product.findMany({
      where,
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
    console.error('Get products error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/products/:id
// @desc    Get single product
// @access  Public
router.get('/:id', async (req, res) => {
  try {
    const product = await prisma.product.findUnique({
      where: { id: req.params.id },
      include: {
        images: true,
        user: {
          select: {
            id: true,
            username: true,
            avatar: true,
            shopName: true,
            isVerified: true,
          },
        },
        _count: {
          select: {
            likes: true,
          },
        },
      },
    });

    if (!product) {
      return res.status(404).json({ message: 'Product not found' });
    }

    // Track product view (async, don't wait for it)
    const userId = req.user?.id;
    prisma.productView.create({
      data: {
        productId: req.params.id,
        ...(userId && { userId }),
      },
    }).catch(err => console.error('Error tracking view:', err));

    res.json(product);
  } catch (error) {
    console.error('Get product error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   POST /api/products
// @desc    Create a product
// @access  Private
router.post('/', protect, upload.array('images', 10), async (req, res) => {
  try {
    const { title, description, price, condition, size, brand, category, tags } = req.body;

    if (!title || !description || !price || !category) {
      return res.status(400).json({ message: 'Missing required fields' });
    }

    // Upload images to Cloudinary
    const imageUploads = [];
    if (req.files && req.files.length > 0) {
      for (const file of req.files) {
        const result = await new Promise((resolve, reject) => {
          cloudinary.uploader
            .upload_stream(
              {
                resource_type: 'image',
                folder: 'thrift-app',
              },
              (error, result) => {
                if (error) reject(error);
                else resolve(result);
              }
            )
            .end(file.buffer);
        });
        imageUploads.push({
          url: result.secure_url,
          publicId: result.public_id,
          isPrimary: imageUploads.length === 0,
        });
      }
    }

    // Parse tags if string, convert to JSON for MySQL
    const tagsArray = typeof tags === 'string' ? JSON.parse(tags) : tags || [];
    const tagsJson = tagsArray.length > 0 ? tagsArray : null;

    const product = await prisma.product.create({
      data: {
        title,
        description,
        price: parseFloat(price),
        condition,
        size,
        brand,
        category,
        tags: tagsJson,
        userId: req.user.id,
        images: {
          create: imageUploads,
        },
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
      },
    });

    res.status(201).json(product);
  } catch (error) {
    console.error('Create product error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   PUT /api/products/:id
// @desc    Update a product
// @access  Private
router.put('/:id', protect, async (req, res) => {
  try {
    const product = await prisma.product.findUnique({
      where: { id: req.params.id },
    });

    if (!product) {
      return res.status(404).json({ message: 'Product not found' });
    }

    if (product.userId !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    const { title, description, price, condition, size, brand, category, tags } = req.body;

    const updatedProduct = await prisma.product.update({
      where: { id: req.params.id },
      data: {
        title,
        description,
        price: price ? parseFloat(price) : undefined,
        condition,
        size,
        brand,
        category,
        tags: tags ? (typeof tags === 'string' ? JSON.parse(tags) : Array.isArray(tags) ? tags : null) : undefined,
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
      },
    });

    res.json(updatedProduct);
  } catch (error) {
    console.error('Update product error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   DELETE /api/products/:id
// @desc    Delete a product
// @access  Private
router.delete('/:id', protect, async (req, res) => {
  try {
    const product = await prisma.product.findUnique({
      where: { id: req.params.id },
      include: { images: true },
    });

    if (!product) {
      return res.status(404).json({ message: 'Product not found' });
    }

    if (product.userId !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    // Delete images from Cloudinary
    for (const image of product.images) {
      if (image.publicId) {
        await cloudinary.uploader.destroy(image.publicId);
      }
    }

    await prisma.product.delete({
      where: { id: req.params.id },
    });

    res.json({ message: 'Product deleted' });
  } catch (error) {
    console.error('Delete product error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   PUT /api/products/:id/sold
// @desc    Mark product as sold
// @access  Private
router.put('/:id/sold', protect, async (req, res) => {
  try {
    const product = await prisma.product.findUnique({
      where: { id: req.params.id },
    });

    if (!product) {
      return res.status(404).json({ message: 'Product not found' });
    }

    if (product.userId !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    const updatedProduct = await prisma.product.update({
      where: { id: req.params.id },
      data: { isSold: true },
    });

    res.json(updatedProduct);
  } catch (error) {
    console.error('Mark sold error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;

