# Create .env file for MySQL setup
$envContent = @"
# Server
PORT=5000
NODE_ENV=development

# Database (MySQL) - root user, no password
DATABASE_URL="mysql://root@localhost:3306/thriftapp"

# JWT
JWT_SECRET=your-super-secret-jwt-key-change-this-in-production-12345
JWT_EXPIRE=7d

# Cloudinary (for image storage) - Add your credentials later
CLOUDINARY_CLOUD_NAME=your-cloud-name
CLOUDINARY_API_KEY=your-api-key
CLOUDINARY_API_SECRET=your-api-secret

# Stripe - Add your credentials later
STRIPE_SECRET_KEY=sk_test_your-stripe-secret-key
STRIPE_WEBHOOK_SECRET=whsec_your-webhook-secret

# Frontend URL
FRONTEND_URL=http://localhost:3000
"@

$envContent | Out-File -FilePath ".env" -Encoding utf8
Write-Host ".env file created successfully!" -ForegroundColor Green

