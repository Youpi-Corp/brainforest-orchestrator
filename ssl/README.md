# SSL Certificate Setup for Production

## 🚀 Automated SSL with Let's Encrypt (Recommended)

The production deployment now includes **automatic SSL certificate management** using Let's Encrypt and Certbot.

### **Quick Setup:**

1. **Configure your domains** in `.env.prod`:

   ```bash
   SSL_EMAIL=admin@yourdomain.com
   DOMAIN_NAME=brain-forest.works
   API_DOMAIN=api.brain-forest.works
   ```

2. **Deploy with automatic SSL**:

   ```powershell
   # Windows
   ./deploy.ps1 deploy

   # Linux/Mac
   ./deploy.sh deploy
   ```

3. **Or initialize SSL separately**:

   ```powershell
   # Windows
   ./deploy.ps1 ssl

   # Linux/Mac
   ./deploy.sh ssl
   ```

### **What Happens Automatically:**

- ✅ **Certificate Generation**: Automatically obtains SSL certificates from Let's Encrypt
- ✅ **Domain Validation**: Uses HTTP-01 challenge via Nginx
- ✅ **Auto-Renewal**: Certificates renew every 12 hours automatically
- ✅ **Multiple Domains**: Supports main domain, www subdomain, and API subdomain
- ✅ **Nginx Integration**: Automatically configures Nginx with new certificates

Your SSL certificates are now fully automated! 🔐✨
