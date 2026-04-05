# Changelog

## 2026-04-05 - Native Deployment + 9Router Integration Fixes

### Fixed
- **9Router Integration**: Removed all Docker-specific references (`host.docker.internal`) and replaced with `127.0.0.1` for native deployment
- **Database Configuration**: Fixed PostgreSQL port from 5434 to 5432 (standard default)
- **Systemd Service**: Corrected Node.js path from `/usr/local/bin/node` to `/usr/bin/node` (matches NodeSource installation)
- **Bash Syntax**: Removed invalid `local` declarations outside functions in all native scripts
- **9Router Detection**: Enhanced localhost binding and API key extraction for native deployment

### Changed
- Migrated from Docker-based deployment to native systemd service
- Updated all scripts to use native paths and configurations
- Improved 9Router auto-detection and configuration sync

### Added
- `scripts/lib/9router-env.sh` - 9Router environment detection and configuration
- `scripts/setup-native.sh` - Native VPS installer
- `scripts/sync-9router-env-native.sh` - 9Router configuration sync for native deployment
- `scripts/reapply-vps-env-native.sh` - VPS environment reapplication
- `scripts/bootstrap-ceo-native.sh` - CEO bootstrap for native deployment
- `scripts/systemd/paperclip.service.template` - Systemd service template

### Removed
- Docker Compose configuration
- Docker-based setup scripts
