const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const http = require('http');
const path = require('path');
const { Server } = require('socket.io');

// Load environment variables
dotenv.config();
if (!process.env.PUBLIC_BASE_URL && process.env.RENDER_EXTERNAL_URL) {
  process.env.PUBLIC_BASE_URL = process.env.RENDER_EXTERNAL_URL;
}

const app = express();
const server = http.createServer(app);
const allowedOrigins = process.env.FRONTEND_URL 
  ? [process.env.FRONTEND_URL] 
  : ['http://localhost:3000', 'http://localhost:19006', 'http://localhost:8081', 'http://localhost:19000'];

const io = new Server(server, {
  cors: {
    origin: allowedOrigins,
    methods: ['GET', 'POST'],
    credentials: true
  }
});

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
  allowedHeaders: ['Content-Type', 'Authorization']
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

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'OK', message: 'popup API is running' });
});

app.get('/u/:username', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'share.html'));
});

// Serve index page at root
app.get('/', (req, res) => {
  res.sendFile(__dirname + '/public/index.html');
});

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
  console.log(`Server running on port ${PORT}`);
});

module.exports = { app, io };

