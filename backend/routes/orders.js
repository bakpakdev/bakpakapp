const express = require('express');
const { PrismaClient } = require('@prisma/client');
const { protect } = require('../middleware/auth');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

const router = express.Router();
const prisma = new PrismaClient();

// @route   POST /api/orders
// @desc    Create an order
// @access  Private
router.post('/', protect, async (req, res) => {
  try {
    const { items, shippingAddress } = req.body;

    if (!items || items.length === 0) {
      return res.status(400).json({ message: 'No items in order' });
    }

    if (!shippingAddress) {
      return res.status(400).json({ message: 'Shipping address required' });
    }

    // Get products and calculate total
    let total = 0;
    const productIds = items.map((item) => item.productId);
    const products = await prisma.product.findMany({
      where: { id: { in: productIds } },
    });

    // Validate products and calculate total
    for (const item of items) {
      const product = products.find((p) => p.id === item.productId);
      if (!product) {
        return res.status(404).json({ message: `Product ${item.productId} not found` });
      }
      if (product.isSold) {
        return res.status(400).json({ message: `Product ${product.title} is already sold` });
      }
      if (product.userId === req.user.id) {
        return res.status(400).json({ message: 'Cannot buy your own product' });
      }
      total += product.price * (item.quantity || 1);
    }

    // Get seller ID (assuming all items from same seller for simplicity)
    const sellerId = products[0].userId;

    // Create Stripe payment intent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: Math.round(total * 100), // Convert to cents
      currency: 'usd',
      metadata: {
        buyerId: req.user.id,
        sellerId: sellerId,
      },
    });

    // Create order
    const order = await prisma.order.create({
      data: {
        total,
        shippingAddress,
        paymentIntentId: paymentIntent.id,
        buyerId: req.user.id,
        sellerId: sellerId,
        items: {
          create: items.map((item) => {
            const product = products.find((p) => p.id === item.productId);
            return {
              productId: item.productId,
              quantity: item.quantity || 1,
              price: product.price,
            };
          }),
        },
      },
      include: {
        items: {
          include: {
            product: {
              include: {
                images: true,
              },
            },
          },
        },
        seller: {
          select: {
            id: true,
            username: true,
            avatar: true,
          },
        },
      },
    });

    // Mark products as sold
    await prisma.product.updateMany({
      where: { id: { in: productIds } },
      data: { isSold: true },
    });

    res.status(201).json({
      order,
      clientSecret: paymentIntent.client_secret,
    });
  } catch (error) {
    console.error('Create order error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/orders
// @desc    Get user's orders
// @access  Private
router.get('/', protect, async (req, res) => {
  try {
    const orders = await prisma.order.findMany({
      where: {
        OR: [{ buyerId: req.user.id }, { sellerId: req.user.id }],
      },
      include: {
        items: {
          include: {
            product: {
              include: {
                images: true,
              },
            },
          },
        },
        buyer: {
          select: {
            id: true,
            username: true,
            avatar: true,
          },
        },
        seller: {
          select: {
            id: true,
            username: true,
            avatar: true,
          },
        },
      },
      orderBy: {
        createdAt: 'desc',
      },
    });

    res.json(orders);
  } catch (error) {
    console.error('Get orders error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/orders/:id
// @desc    Get single order
// @access  Private
router.get('/:id', protect, async (req, res) => {
  try {
    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
      include: {
        items: {
          include: {
            product: {
              include: {
                images: true,
              },
            },
          },
        },
        buyer: {
          select: {
            id: true,
            username: true,
            avatar: true,
          },
        },
        seller: {
          select: {
            id: true,
            username: true,
            avatar: true,
          },
        },
      },
    });

    if (!order) {
      return res.status(404).json({ message: 'Order not found' });
    }

    if (order.buyerId !== req.user.id && order.sellerId !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    res.json(order);
  } catch (error) {
    console.error('Get order error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   PUT /api/orders/:id/status
// @desc    Update order status
// @access  Private
router.put('/:id/status', protect, async (req, res) => {
  try {
    const { status } = req.body;
    const validStatuses = ['pending', 'processing', 'shipped', 'delivered', 'cancelled'];

    if (!validStatuses.includes(status)) {
      return res.status(400).json({ message: 'Invalid status' });
    }

    const order = await prisma.order.findUnique({
      where: { id: req.params.id },
    });

    if (!order) {
      return res.status(404).json({ message: 'Order not found' });
    }

    // Only seller can update status
    if (order.sellerId !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    const updatedOrder = await prisma.order.update({
      where: { id: req.params.id },
      data: { status },
      include: {
        items: {
          include: {
            product: {
              include: {
                images: true,
              },
            },
          },
        },
      },
    });

    res.json(updatedOrder);
  } catch (error) {
    console.error('Update order status error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   POST /api/orders/webhook
// @desc    Stripe webhook handler
// @access  Public (Stripe calls this)
router.post('/webhook', express.raw({ type: 'application/json' }), async (req, res) => {
  const sig = req.headers['stripe-signature'];

  let event;

  try {
    event = stripe.webhooks.constructEvent(req.body, sig, process.env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    return res.status(400).send(`Webhook signature verification failed. ${err.message}`);
  }

  // Handle the event
  if (event.type === 'payment_intent.succeeded') {
    const paymentIntent = event.data.object;
    // Update order status
    await prisma.order.updateMany({
      where: { paymentIntentId: paymentIntent.id },
      data: { status: 'processing' },
    });
  }

  res.json({ received: true });
});

module.exports = router;

