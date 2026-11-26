# Nhóm 04: Telegram Đa Bot, AI Sentinel, Kho Key Đa Tài Khoản & Kết Nối Từ Xa

Lưu trữ khóa bảo mật chmod 600 (Zero-Leak Vault), cảnh báo Telegram nhiều Bot, tích hợp Tailscale VPN / Funnel HTTPS, đường hầm tạm thời và khóa bảo vệ chặn mở cổng WAN khi chưa đặt mật khẩu root.

## Danh Sách Kịch Bản Độc Lập Trong Nhóm Này

> Khi nâng cấp hoặc sửa lỗi nhóm `04-sentinel-telegram-remote`, **chỉ chỉnh sửa các tệp trong bảng dưới đây**, tuyệt đối không tác động sang 5 nhóm còn lại.

| Đường dẫn trong GitHub Repo | Đường dẫn trên Router OpenWrt | Quyền |
| :--- | :--- | :---: |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/doanduy.vault` | `/usr/libexec/rpcd/doanduy.vault` | `755` |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/doanduy.remote` | `/usr/libexec/rpcd/doanduy.remote` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/send_telegram` | `/usr/bin/send_telegram` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/doanduy_remote_auto.sh` | `/usr/bin/doanduy_remote_auto.sh` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/remote_web_tunnel.sh` | `/usr/bin/remote_web_tunnel.sh` | `755` |
| `luci-app-doanduy-modem/root/etc/init.d/doanduy_auto` | `/etc/init.d/doanduy_auto` | `755` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/doanduy/tab_sentinel.js` | `/www/luci-static/resources/doanduy/tab_sentinel.js` | `644` |

## Lệnh Kiểm Tra & Triển Khai Riêng Nhóm Này

- **Trên máy tính Windows (PowerShell)**:
  ```powershell
  # Chỉ kiểm tra cú pháp, LF & JSON riêng nhóm 04-sentinel-telegram-remote:
  .\scenarios\04-sentinel-telegram-remote\check.ps1

  # Chỉ đẩy nóng riêng nhóm 04-sentinel-telegram-remote lên Router thật (không đụng 5 nhóm kia):
  .\scenarios\04-sentinel-telegram-remote\deploy.ps1 -Router 192.168.1.1
  ```
- **Trên Linux / Máy chủ Lab / GitHub Actions**:
  ```sh
  sh scenarios/run_scenario.sh check 04-sentinel-telegram-remote
  ```
