# AmneziaWG Manager

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Linux-blue.svg)]()
[![Version](https://img.shields.io/badge/Version-2.0-green.svg)]()

AmneziaWG Manager is a comprehensive solution for initializing and managing an AmneziaWG VPN server and its users. This tool simplifies the process of setting up a secure, high-performance WireGuard-based VPN with additional Amnezia protocol enhancements.

## Features

- **Single-command server setup**: Initialize your VPN server with just one command
- **User management**: Easily create, delete, lock, and unlock user accounts
- **Configuration generation**: Automatically generate and export client configurations
- **QR code support**: Generate QR codes for easy mobile client setup
- **Robust error handling**: Comprehensive logging and error reporting
- **Security focused**: Follows best practices for VPN configuration and key management

## System Requirements

- Ubuntu 20.04/22.04 or Debian 10+
- Root access
- Public IP address or domain name

## Quick Start

### Server Installation

Run this command on your Ubuntu or Debian server:

```bash
sudo bash -c "$(curl -sL https://raw.githubusercontent.com/bkeenke/awg-manager/master/init.sh)" @ install
```

This will:
1. Install all necessary dependencies
2. Set up AmneziaWG components
3. Configure your system for VPN operation

### Server Initialization

After installation, initialize the server with your public IP or domain:

```bash
sudo /etc/amnezia/amneziawg/awg-manager.sh -i -s YOUR_SERVER_IP_OR_DOMAIN
```

### User Management

#### Create a new user

```bash
sudo /etc/amnezia/amneziawg/awg-manager.sh -u username -c
```

#### Generate a user configuration file

```bash
sudo /etc/amnezia/amneziawg/awg-manager.sh -u username -p > username.conf
```

#### Generate a QR code for mobile clients

```bash
sudo /etc/amnezia/amneziawg/awg-manager.sh -u username -q
```

#### Disable a user temporarily (lock)

```bash
sudo /etc/amnezia/amneziawg/awg-manager.sh -u username -L
```

#### Re-enable a user (unlock)

```bash
sudo /etc/amnezia/amneziawg/awg-manager.sh -u username -U
```

#### Delete a user permanently

```bash
sudo /etc/amnezia/amneziawg/awg-manager.sh -u username -d
```

## Manual Installation

If you prefer to install components individually:

### 1. Install prerequisites

```bash
apt update && apt upgrade -y
apt install build-essential curl make git wget qrencode python3 python3-pip iptables net-tools -y
```

### 2. Install Go

```bash
mkdir -p /opt/go
cd /opt/go
wget https://go.dev/dl/go1.22.2.linux-amd64.tar.gz
rm -rf /usr/local/go && tar -C /usr/local -xzf go1.22.2.linux-amd64.tar.gz
echo "export PATH=$PATH:/usr/local/go/bin" >> /etc/profile
source /etc/profile
```

### 3. Install AmneziaWG Go

```bash
git clone https://github.com/amnezia-vpn/amneziawg-go.git /opt/amnezia-go
cd /opt/amnezia-go
make
cp /opt/amnezia-go/amneziawg-go /usr/bin/amneziawg-go
chmod 755 /usr/bin/amneziawg-go
```

### 4. Install AmneziaWG Tools

```bash
git clone https://github.com/amnezia-vpn/amneziawg-tools.git /opt/amnezia-tools
cd /opt/amnezia-tools/src
make
make install
```

### 5. Install Python requirements

```bash
pip3 install PyQt6
```

### 6. Download AmneziaWG Manager

```bash
mkdir -p /etc/amnezia/amneziawg
wget -O /etc/amnezia/amneziawg/awg-manager.sh https://raw.githubusercontent.com/bkeenke/awg-manager/master/awg-manager.sh
chmod 700 /etc/amnezia/amneziawg/awg-manager.sh
wget -O /etc/amnezia/amneziawg/encode.py https://raw.githubusercontent.com/bkeenke/awg-manager/master/encode.py
```

## Using AmneziaWG with existing clients

Users can connect to your AmneziaWG server using:

1. **AmneziaVPN Client** (recommended): Compatible with Windows, macOS, Android, and iOS
2. **Standard WireGuard client**: Requires manual configuration adjustments

## Security Recommendations

For production deployments, we recommend:

1. **Firewall rules**: Configure your firewall to only allow traffic on the VPN port (default: 39547/UDP)
2. **Regular updates**: Keep your system and AmneziaWG components updated
3. **User auditing**: Regularly review active users and revoke access when no longer needed
4. **Secure key storage**: Protect client configuration files and keep backups
5. **Monitoring**: Enable system logs and monitor for unusual activity

## Troubleshooting

Common issues and solutions:

### Server issues
- **Connection failures**: Check firewall settings and ensure port 39547/UDP is open
- **Installation errors**: Verify system requirements and check `/var/log/amnezia-install.log`
- **Server not starting**: Run `systemctl status awg-quick@awg0` for detailed errors

### Client issues
- **Configuration problems**: Regenerate client configuration files
- **Connection drops**: Try adjusting the `PersistentKeepalive` parameter
- **QR code scanning issues**: Ensure proper lighting and try exporting the configuration file instead

## Command Reference

```
Usage: ./awg-manager.sh [<options>] [command [arg]]
Options:
 -i : Init (Create server keys and configs)
 -c : Create new user
 -d : Delete user
 -L : Lock user
 -U : Unlock user
 -p : Print user config
 -q : Print user QR code
 -u <user> : User identifier (uniq field for vpn account)
 -s <server> : Server host for user connection
 -I <interface> : Network interface (default: auto-detect) 
 -D <dns> : DNS servers (default: 1.1.1.1, 8.8.8.8)
 -P <port> : Server port (default: 39547)
 -h : Usage
```

## Logs and Debugging

- Installation logs: `/var/log/amnezia-install.log`
- Manager logs: `/var/log/amnezia-manager.log`
- Encoder logs: `/var/log/amnezia-encoder.log`
- System logs: `journalctl -u awg-quick@awg0`

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Based on the AmneziaVPN project
- Uses modified WireGuard components (amneziawg-go, amneziawg-tools)
- Thanks to all contributors and the WireGuard project

---

**Note**: This software is provided as-is, without warranty of any kind. Always perform thorough testing before deploying in production environments.

