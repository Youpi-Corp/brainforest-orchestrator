# 🌳 Brain Forest - One Command Deployment

Deploy your entire Brain Forest application with HTTPS in a single command!

## 🚀 Quick Start

### Windows (PowerShell):

```powershell
# 1. Setup environment (first time only)
Copy-Item .env.prod.example .env.prod
# Edit .env.prod with your settings

# 2. Deploy everything!
.\deploy.ps1
```

### Linux/macOS (Terminal):

```bash
# 1. Setup environment (first time only)
cp .env.prod.example .env.prod
# Edit .env.prod with your settings

# 2. Make script executable and deploy!
chmod +x deploy.sh
./deploy.sh deploy
```

That's it! Your app will be running at:

- **HTTP:** http://your-domain.com (redirects to HTTPS)
- **HTTPS:** https://your-domain.com ✨

## 📋 Prerequisites

- Docker and Docker Compose installed
- **Linux users:** Add your user to docker group: `sudo usermod -aG docker $USER` (then logout/login)
- **Domain setup:** Your domain's DNS must point to your server's IP address

## ⚙️ Environment Setup

Edit `.env.prod` with your settings:

```env
# Required: Set a secure database password
POSTGRES_PASSWORD=your-secure-password-here

# Required for HTTPS: Set your domain and email
DOMAIN_NAME=your-domain.com
SSL_EMAIL=your-email@example.com

# Optional: Customize if needed
NODE_ENV=production
```

## 🎯 Available Commands

### Windows:

```powershell
.\deploy.ps1                          # Deploy with HTTPS
.\deploy.ps1 status                   # Check status
.\deploy.ps1 logs                     # View all logs
.\deploy.ps1 logs -Service nginx      # View specific service logs
.\deploy.ps1 stop                     # Stop all services
.\deploy.ps1 restart                  # Restart services
.\deploy.ps1 backup                   # Create database backup
.\deploy.ps1 clean -Force             # Clean Docker resources
```

### Linux/macOS:

```bash
./deploy.sh deploy                    # Deploy with HTTPS
./deploy.sh status                    # Check status
./deploy.sh ssl                       # Check SSL certificate status
./deploy.sh logs --service certbot    # View SSL certificate logs
./deploy.sh stop                      # Stop all services
./deploy.sh clean --force             # Clean everything
```

## 🔧 What the deployment includes:

- ✅ **Frontend** (React app)
- ✅ **Backend** (Node.js API)
- ✅ **Database** (PostgreSQL with automatic backups)
- ✅ **Nginx** (Reverse proxy with HTTPS)
- ✅ **SSL Certificates** (Automatic Let's Encrypt with auto-renewal)
- ✅ **Health checks** and monitoring
- ✅ **Automatic restart** on failure

## 🔐 HTTPS & SSL

The deployment automatically:

- ✅ Obtains SSL certificates from Let's Encrypt
- ✅ Configures HTTPS with your domain
- ✅ Redirects HTTP to HTTPS
- ✅ Auto-renews certificates every 12 hours
- ✅ Supports multiple domains (www.your-domain.com)

## 🐛 Troubleshooting

**Services not starting?**

```bash
./deploy.sh status    # Check what's running
./deploy.sh logs      # Check for errors
```

**SSL certificate issues?**

```bash
./deploy.sh ssl                    # Check certificate status
./deploy.sh logs --service certbot # Check certificate logs
```

**Domain not working?**

1. Verify DNS: `nslookup your-domain.com`
2. Check ports 80 & 443 are open
3. Wait for DNS propagation (up to 24 hours)

**Need to reset everything?**

```bash
./deploy.sh clean --force
./deploy.sh deploy
```

## 📁 Project Structure

```
brainforest/
├── deploy.ps1              # Windows deployment script
├── deploy.sh               # Linux deployment script
├── docker-compose.yml      # Docker configuration with HTTPS
├── .env.prod               # Environment settings
├── nginx/                  # Nginx configuration
├── leaves/                 # Frontend app
├── sap/                    # Backend API
└── backups/                # Database backups
```

## 🎉 That's it!

The deployment script handles everything automatically:

- Building Docker images
- Setting up HTTPS with SSL certificates
- Starting services with nginx reverse proxy
- Creating database backups
- Health monitoring
- Error handling

No complex configuration needed - just set your domain and run the deploy command! 🌳✨

## 🌐 Accessing Your App

After deployment:

- **Main site:** https://your-domain.com
- **With www:** https://www.your-domain.com
- **Local testing:** http://localhost (if accessing from server)

All HTTP traffic automatically redirects to HTTPS for security! 🔒
