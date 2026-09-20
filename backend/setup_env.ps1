# Create .env file for local backend / Stripe setup
# Prefer copying backend/.env.example -> backend/.env and filling secrets there.
# Do not put live secret keys in this script.
$envContent = @"
# Server
PORT=5001
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

# Supabase
SUPABASE_URL=https://your-project-ref.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-supabase-service-role-key

# Stripe
STRIPE_SECRET_KEY=sk_test_your_secret_key
STRIPE_PUBLISHABLE_KEY=pk_test_your_publishable_key
STRIPE_WEBHOOK_SECRET=whsec_your-webhook-secret
PUBLIC_BASE_URL=http://localhost:5001
STRIPE_CONNECT_REFRESH_URL=http://localhost:5001/auth/verified.html?stripe=refresh
STRIPE_CONNECT_RETURN_URL=http://localhost:5001/auth/verified.html?stripe=return

# Frontend URL
FRONTEND_URL=http://localhost:3000
"@

$envContent | Out-File -FilePath ".env" -Encoding utf8
Write-Host ".env file created successfully!" -ForegroundColor Green
