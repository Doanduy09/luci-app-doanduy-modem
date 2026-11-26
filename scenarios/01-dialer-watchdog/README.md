# Nhóm 01: Trình Quay Số 5G Thông Minh (USB & PCIe) & Watchdog Tự Phục Hồi

Quản lý kết nối 5G netifd (duydoan5g), tự động dò card USB/PCIe (Quectel, Fibocom, Sierra, SIMCom), khóa flock chống xung đột cổng AT và tự phục hồi mạng 3 tầng.

## Danh Sách Kịch Bản Độc Lập Trong Nhóm Này

> Khi nâng cấp hoặc sửa lỗi nhóm `01-dialer-watchdog`, **chỉ chỉnh sửa các tệp trong bảng dưới đây**, tuyệt đối không tác động sang 5 nhóm còn lại.

| Đường dẫn trong GitHub Repo | Đường dẫn trên Router OpenWrt | Quyền |
| :--- | :--- | :---: |
| `luci-app-doanduy-modem/root/usr/bin/duydoan5g_dialer.sh` | `/usr/bin/duydoan5g_dialer.sh` | `755` |
| `luci-app-doanduy-modem/root/lib/netifd/proto/duydoan5g.sh` | `/lib/netifd/proto/duydoan5g.sh` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/smart_modem_watchdog.sh` | `/usr/bin/smart_modem_watchdog.sh` | `755` |
| `luci-app-doanduy-modem/root/etc/init.d/smart_modem_watchdog` | `/etc/init.d/smart_modem_watchdog` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/modem_lock_run` | `/usr/bin/modem_lock_run` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/restart_wwan` | `/usr/bin/restart_wwan` | `755` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/protocol/duydoan5g.js` | `/www/luci-static/resources/protocol/duydoan5g.js` | `644` |

## Lệnh Kiểm Tra & Triển Khai Riêng Nhóm Này

- **Trên máy tính Windows (PowerShell)**:
  ```powershell
  # Chỉ kiểm tra cú pháp, LF & JSON riêng nhóm 01-dialer-watchdog:
  .\scenarios\01-dialer-watchdog\check.ps1

  # Chỉ đẩy nóng riêng nhóm 01-dialer-watchdog lên Router thật (không đụng 5 nhóm kia):
  .\scenarios\01-dialer-watchdog\deploy.ps1 -Router 192.168.1.1
  ```
- **Trên Linux / Máy chủ Lab / GitHub Actions**:
  ```sh
  sh scenarios/run_scenario.sh check 01-dialer-watchdog
  ```
