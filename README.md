# 🌳 Brain Forest - One Command Deployment

Deploy your entire Brain Forest application with a single command!

## 🚀 Quick Start

```powershell
# 1. Setup environment (first time only)
Copy-Item .env.prod.example .env.prod
# Edit .env.prod with your database password

# 2. Deploy everything!
.\deploy.ps1
```

That's it! Your app will be running at:

- **Frontend:** http://localhost:8080
- **Backend:** http://localhost:3000

## 📋 Prerequisites

- Docker Desktop installed and running
- PowerShell (Windows) or Terminal (Linux/Mac)

## ⚙️ Environment Setup

Edit `.env.prod` with your settings:

```env
# Required: Set a secure database password
POSTGRES_PASSWORD=your-secure-password-here

# Optional: Add other settings as needed
```

## 🎯 Available Commands

```powershell
.\deploy.ps1                          # Deploy application
.\deploy.ps1 status                   # Check status
.\deploy.ps1 logs                     # View all logs
.\deploy.ps1 logs -Service backend    # View specific service logs
.\deploy.ps1 stop                     # Stop all services
.\deploy.ps1 restart                  # Restart services
.\deploy.ps1 backup                   # Create database backup
.\deploy.ps1 clean -Force             # Clean Docker resources
```

## 🔧 What the deployment includes:

- ✅ **Frontend** (React app on port 8080)
- ✅ **Backend** (Node.js API on port 3000)
- ✅ **Database** (PostgreSQL with automatic backups)
- ✅ **Health checks** and monitoring
- ✅ **Automatic restart** on failure

## 🐛 Troubleshooting

**Services not starting?**

```powershell
.\deploy.ps1 status    # Check what's running
.\deploy.ps1 logs      # Check for errors
```

**Need to reset everything?**

```powershell
.\deploy.ps1 clean -Force
.\deploy.ps1 deploy
```

**Database issues?**

```powershell
.\deploy.ps1 logs -Service db
```

## 📁 Project Structure

```
brainforest/
├── deploy.ps1              # Main deployment script
├── docker-compose.yml      # Docker configuration
├── .env.prod               # Environment settings
├── leaves/                 # Frontend app
├── sap/                    # Backend API
└── backups/                # Database backups
```

## 🎉 That's it!

The deployment script handles everything automatically:

- Building Docker images
- Starting services
- Creating database backups
- Health monitoring
- Error handling

No complex configuration needed - just run `.\deploy.ps1` and you're good to go! 🌳
