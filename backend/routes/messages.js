const express = require('express');
const { PrismaClient } = require('@prisma/client');
const { protect } = require('../middleware/auth');

const router = express.Router();
const prisma = new PrismaClient();

// @route   GET /api/messages/conversations
// @desc    Get user's conversations
// @access  Private
router.get('/conversations', protect, async (req, res) => {
  try {
    const conversations = await prisma.conversation.findMany({
      where: {
        participants: {
          some: {
            userId: req.user.id,
          },
        },
      },
      include: {
        participants: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                avatar: true,
              },
            },
          },
        },
        messages: {
          orderBy: {
            createdAt: 'desc',
          },
          take: 1,
        },
      },
      orderBy: {
        updatedAt: 'desc',
      },
    });

    // Transform participants to match expected format
    const transformedConversations = conversations.map(conv => ({
      ...conv,
      participants: conv.participants.map(p => p.user),
    }));

    res.json(transformedConversations);
  } catch (error) {
    console.error('Get conversations error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/messages/conversations/:id
// @desc    Get or create conversation between two users
// @access  Private
router.get('/conversations/:otherUserId', protect, async (req, res) => {
  try {
    // Find existing conversation
    let conversation = await prisma.conversation.findFirst({
      where: {
        participants: {
          some: {
            userId: req.user.id,
          },
        },
        AND: {
          participants: {
            some: {
              userId: req.params.otherUserId,
            },
          },
        },
      },
      include: {
        participants: {
          include: {
            user: {
              select: {
                id: true,
                username: true,
                avatar: true,
              },
            },
          },
        },
        messages: {
          orderBy: {
            createdAt: 'asc',
          },
        },
      },
    });

    // Create if doesn't exist
    if (!conversation) {
      conversation = await prisma.conversation.create({
        data: {
          participants: {
            create: [
              { userId: req.user.id },
              { userId: req.params.otherUserId },
            ],
          },
        },
        include: {
          participants: {
            include: {
              user: {
                select: {
                  id: true,
                  username: true,
                  avatar: true,
                },
              },
            },
          },
          messages: [],
        },
      });
    }

    // Transform participants
    const transformedConversation = {
      ...conversation,
      participants: conversation.participants.map(p => p.user),
    };

    res.json(transformedConversation);
  } catch (error) {
    console.error('Get conversation error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   POST /api/messages
// @desc    Send a message
// @access  Private
router.post('/', protect, async (req, res) => {
  try {
    const { conversationId, content } = req.body;

    if (!content || !conversationId) {
      return res.status(400).json({ message: 'Content and conversation ID required' });
    }

    // Verify user is part of conversation
    const conversation = await prisma.conversation.findUnique({
      where: { id: conversationId },
      include: {
        participants: {
          include: {
            user: true,
          },
        },
      },
    });

    if (!conversation) {
      return res.status(404).json({ message: 'Conversation not found' });
    }

    const isParticipant = conversation.participants.some((p) => p.userId === req.user.id);
    if (!isParticipant) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    const message = await prisma.message.create({
      data: {
        content,
        senderId: req.user.id,
        conversationId,
      },
      include: {
        sender: {
          select: {
            id: true,
            username: true,
            avatar: true,
          },
        },
      },
    });

    // Update conversation updatedAt
    await prisma.conversation.update({
      where: { id: conversationId },
      data: { updatedAt: new Date() },
    });

    res.status(201).json(message);
  } catch (error) {
    console.error('Send message error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

// @route   GET /api/messages/:conversationId
// @desc    Get messages in a conversation
// @access  Private
router.get('/:conversationId', protect, async (req, res) => {
  try {
    const conversation = await prisma.conversation.findUnique({
      where: { id: req.params.conversationId },
      include: {
        participants: {
          include: {
            user: true,
          },
        },
        messages: {
          include: {
            sender: {
              select: {
                id: true,
                username: true,
                avatar: true,
              },
            },
          },
          orderBy: {
            createdAt: 'asc',
          },
        },
      },
    });

    if (!conversation) {
      return res.status(404).json({ message: 'Conversation not found' });
    }

    const isParticipant = conversation.participants.some((p) => p.userId === req.user.id);
    if (!isParticipant) {
      return res.status(403).json({ message: 'Not authorized' });
    }

    // Mark messages as read
    await prisma.message.updateMany({
      where: {
        conversationId: req.params.conversationId,
        senderId: { not: req.user.id },
        isRead: false,
      },
      data: { isRead: true },
    });

    res.json(conversation.messages);
  } catch (error) {
    console.error('Get messages error:', error);
    res.status(500).json({ message: 'Server error', error: error.message });
  }
});

module.exports = router;

