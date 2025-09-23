const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

const PORT = process.env.PORT || 3000;

let passphrase = crypto.randomBytes(8).toString('hex');
let currentPDF = null;
let currentPage = 1;
let presenterSocket = null;
let viewers = new Set();

console.log(`🔐 Presenter passphrase: ${passphrase}`);

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const uploadDir = 'uploads/';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    cb(null, Date.now() + '-' + file.originalname);
  }
});

const upload = multer({ 
  storage: storage,
  fileFilter: (req, file, cb) => {
    if (file.mimetype === 'application/pdf') {
      cb(null, true);
    } else {
      cb(new Error('Only PDF files are allowed'));
    }
  }
});

app.use(express.static('public'));
app.use('/uploads', express.static('uploads'));
app.use(express.json());

app.post('/upload', upload.single('pdf'), (req, res) => {
  // Verify passphrase
  const providedPassphrase = req.body.passphrase;
  if (providedPassphrase !== passphrase) {
    return res.status(401).json({ error: 'Invalid passphrase' });
  }

  if (!req.file) {
    return res.status(400).json({ error: 'No PDF file uploaded' });
  }
  
  const pdfUrl = `/uploads/${req.file.filename}`;
  res.json({ 
    success: true, 
    pdfUrl: pdfUrl,
    filename: req.file.originalname 
  });
});

app.get('/', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
});

app.get('/presenter', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'presenter.html'));
});

app.get('/viewer', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'viewer.html'));
});

io.on('connection', (socket) => {
  console.log(`📱 Client connected: ${socket.id}`);

  socket.on('presenter_auth', (data) => {
    if (data.passphrase === passphrase) {
      if (presenterSocket) {
        presenterSocket.emit('auth_error', { message: 'Another presenter is already connected' });
        return;
      }
      
      presenterSocket = socket;
      socket.isPresenter = true;
      socket.emit('auth_success', { message: 'Presenter authenticated successfully' });
      console.log(`🎯 Presenter authenticated: ${socket.id}`);
      
      if (currentPDF) {
        socket.emit('pdf_status', { pdfUrl: currentPDF, currentPage: currentPage });
      }
    } else {
      socket.emit('auth_error', { message: 'Invalid passphrase' });
    }
  });

  socket.on('viewer_join', () => {
    viewers.add(socket);
    socket.isViewer = true;
    console.log(`👁️  Viewer joined: ${socket.id} (${viewers.size} total viewers)`);
    
    if (currentPDF) {
      socket.emit('pdf_update', { pdfUrl: currentPDF, currentPage: currentPage });
    }
  });

  socket.on('set_pdf', (data) => {
    if (!socket.isPresenter) {
      socket.emit('error', { message: 'Unauthorized: Only presenter can set PDF' });
      return;
    }
    
    currentPDF = data.pdfUrl;
    currentPage = 1;
    console.log(`📄 PDF set by presenter: ${currentPDF}`);
    
    viewers.forEach(viewer => {
      viewer.emit('pdf_update', { pdfUrl: currentPDF, currentPage: currentPage });
    });
  });

  socket.on('page_change', (data) => {
    if (!socket.isPresenter) {
      socket.emit('error', { message: 'Unauthorized: Only presenter can change pages' });
      return;
    }
    
    currentPage = data.page;
    console.log(`📖 Page changed to: ${currentPage}`);
    
    viewers.forEach(viewer => {
      viewer.emit('page_update', { currentPage: currentPage });
    });
  });

  socket.on('disconnect', () => {
    console.log(`📱 Client disconnected: ${socket.id}`);
    
    if (socket.isPresenter) {
      presenterSocket = null;
      console.log('🎯 Presenter disconnected');
      
      passphrase = crypto.randomBytes(8).toString('hex');
      console.log(`🔐 New presenter passphrase: ${passphrase}`);
    }
    
    if (socket.isViewer) {
      viewers.delete(socket);
      console.log(`👁️  Viewer left: ${socket.id} (${viewers.size} remaining viewers)`);
    }
  });
});

server.listen(PORT, () => {
  console.log(`🚀 Sync PDF Viewer server running on port ${PORT}`);
  console.log(`📋 Presenter: http://localhost:${PORT}/presenter`);
  console.log(`👀 Viewer: http://localhost:${PORT}/viewer`);
  console.log(`🔐 Presenter passphrase: ${passphrase}`);
});
