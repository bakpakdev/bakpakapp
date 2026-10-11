const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');

// Load environment variables
dotenv.config();
if (!process.env.PUBLIC_BASE_URL) {
  const railway = process.env.RAILWAY_PUBLIC_DOMAIN;
  const fly = process.env.FLY_PUBLIC_URL;
  const render = process.env.RENDER_EXTERNAL_URL;
  if (railway) {
    process.env.PUBLIC_BASE_URL = railway.startsWith('http') ? railway : `https://${railway}`;
  } else if (fly) {
    process.env.PUBLIC_BASE_URL = fly;
  } else if (render) {
    process.env.PUBLIC_BASE_URL = render;
  }
}

const app = express();
const server = http.createServer(app);

// Register health BEFORE any other route requires so Render/load balancers still
// get a 200 even if Prisma/Square/etc fail to boot.
app.get('/api/health', (_req, res) => {
  res.status(200).json({ status: 'OK', message: 'popup API is running' });
});
app.get('/healthz', (_req, res) => {
  res.status(200).json({ status: 'OK' });
});

const allowedOrigins = process.env.FRONTEND_URL
  ? [process.env.FRONTEND_URL]
  : ['http://localhost:3000', 'http://localhost:19006', 'http://localhost:8081', 'http://localhost:19000'];

const io = new Server(server, {
  cors: {
    origin: allowedOrigins,
    methods: ['GET', 'POST'],
    credentials: true,
  },
});

let routesReady = false;
let bootError = null;

try {
  // Square webhooks must receive raw body (register before express.json()).
  const { squareWebhookHandler } = require('./routes/square');
  app.post(
    '/api/payments/square/webhook',
    express.raw({ type: 'application/json' }),
    squareWebhookHandler
  );

  // Middleware
  app.use(cors({
    origin: function (origin, callback) {
      // Allow requests with no origin (like mobile apps or curl requests)
      if (!origin) return callback(null, true);
      if (allowedOrigins.indexOf(origin) !== -1) {
        callback(null, true);
      } else {
        callback(null, true); // Allow all origins for development
      }
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization'],
  }));
  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true, limit: '10mb' }));
  app.use(express.static('public')); // Serve static files

  // Routes
  app.use('/api/auth', require('./routes/auth'));
  app.use('/api/users', require('./routes/users'));
  app.use('/api/products', require('./routes/products'));
  app.use('/api/orders', require('./routes/orders'));
  app.use('/api/messages', require('./routes/messages'));
  app.use('/api/search', require('./routes/search'));
  app.use('/api/discover', require('./routes/discover'));
  app.use('/api/cart', require('./routes/cart'));
  app.use('/api/social', require('./routes/social'));
  app.use('/api/payments', require('./routes/payments'));
  app.use('/api/payments/square', require('./routes/square'));
  app.use('/api/identify-clothing', require('./routes/identify'));
  app.use('/api/auth/sms-2fa', require('./routes/sms2fa'));

  app.get('/u/:username', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'share.html'));
  });

  app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, 'public', 'index.html'));
  });

  routesReady = true;
} catch (err) {
  bootError = err;
  console.error('Failed to load API routes:', err);
  app.get('/', (_req, res) => {
    res.status(503).json({
      status: 'DEGRADED',
      message: 'API routes failed to load',
      error: String(err && err.message ? err.message : err),
    });
  });
}

// Socket.io for real-time messaging
io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  socket.on('join-conversation', (conversationId) => {
    socket.join(`conversation-${conversationId}`);
  });

  socket.on('leave-conversation', (conversationId) => {
    socket.leave(`conversation-${conversationId}`);
  });

  socket.on('send-message', (data) => {
    socket.to(`conversation-${data.conversationId}`).emit('receive-message', data);
  });

  socket.on('disconnect', () => {
    console.log('User disconnected:', socket.id);
  });
});

// Default 5001: on macOS, port 5000 is often AirPlay Receiver (HTTP → 403), which breaks Expo/iOS Simulator talking to "the API".
const PORT = process.env.PORT || 5001;

server.listen(PORT, () => {
  console.log(`Server running on port ${PORT} (routesReady=${routesReady})`);
  if (bootError) {
    console.error('Boot completed with route load error:', bootError);
  }
});

module.exports = { app, io };
