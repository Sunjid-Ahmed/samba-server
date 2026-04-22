# 📦 Samba Server Manager

A Bash-based GUI tool to simplify Samba server configuration and management on Linux systems. Built using **Zenity**, this project provides an interactive interface for managing file shares, users, services, and automated backups without manually editing configuration files.

---

## 🚀 Features

### 🔧 Installation

* One-click setup for required packages:

  * `samba`
  * `zenity`
  * `inotify-tools`
* Automatically prepares `/samba` directory and backup storage

### 📁 Share Management

* Create public (no password) or private (password-protected) shares
* View all user-defined shares
* Delete shares safely with config backup

### 👤 User Management

* Add new Samba users
* Delete users (including system account removal)
* List all existing Samba users

### ⚙️ Service Control

* Start, stop, and restart Samba service (`smbd`)
* Instant GUI feedback

### 🔄 Auto Backup & Monitoring

* Real-time folder monitoring using `inotify`
* Automatic `.tar.gz` backups on file changes
* Background monitoring with PID tracking

### 🗂️ Backup Manager

* View available backup files
* Inspect backup contents
* Restore backups to any directory

### 📜 Logging

* Logs all monitored events and backup operations
* View logs through GUI

---

## ⚙️ How It Works

This script provides a menu-driven GUI that interacts with system-level Samba configurations. It automates tasks like:

* Editing `/etc/samba/smb.conf`
* Managing users via `smbpasswd`
* Handling file permissions and backups

All operations are executed securely with root privileges.

---

## 🛠️ Requirements

* Linux (Debian/Ubuntu recommended)
* Root access (`sudo`)
* Required packages:

  * samba
  * zenity
  * inotify-tools

---

## ▶️ Installation & Usage

```bash
git clone https://github.com/your-username/samba-server-manager.git
cd samba-server-manager
chmod +x samba-server.sh
sudo ./samba-server.sh
```

---

## 📌 Notes

* Must be run with **root privileges**
* Automatically creates:

  * `/samba` (for shares)
  * `/var/backups/samba` (for backups)
  * `/var/log/samba_gui.log` (for logs)

---

## ⚠️ Disclaimer

This tool modifies system-level configurations. Use it carefully in production environments. Always keep backups of your Samba configuration before making major changes.

---

## 📈 Future Improvements

* Web-based interface
* Role-based access control
* Remote server management
* Backup scheduling options

---

## 👨‍💻 Author

**Sunjid Ahmed Siyem**
Cybersecurity Enthusiast | CSE Student
