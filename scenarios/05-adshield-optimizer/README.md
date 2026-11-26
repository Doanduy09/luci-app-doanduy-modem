# Nhóm 05: Chặn Quảng Cáo AdShield, Tối Ưu Phần Cứng, Đọc Log & Khung Hệ Thống

Chặn quảng cáo/cờ bạc DNS Sinkhole + nftables 53/853, tối ưu phần cứng chuyên sâu MediaTek Filogic WED & Qualcomm NSS, công cụ đọc log, trình cài đặt kép opkg/apk và khung điều hướng chính.

## Danh Sách Kịch Bản Độc Lập Trong Nhóm Này

> Khi nâng cấp hoặc sửa lỗi nhóm `05-adshield-optimizer`, **chỉ chỉnh sửa các tệp trong bảng dưới đây**, tuyệt đối không tác động sang 5 nhóm còn lại.

| Đường dẫn trong GitHub Repo | Đường dẫn trên Router OpenWrt | Quyền |
| :--- | :--- | :---: |
| `luci-app-doanduy-modem/root/usr/bin/adshield` | `/usr/bin/adshield` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/clean_dns.sh` | `/usr/bin/clean_dns.sh` | `755` |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/doanduy.adshield` | `/usr/libexec/rpcd/doanduy.adshield` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/device_opt.sh` | `/usr/bin/device_opt.sh` | `755` |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/doanduy.opt` | `/usr/libexec/rpcd/doanduy.opt` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/doanduy_pkg_helper.sh` | `/usr/bin/doanduy_pkg_helper.sh` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/logall` | `/usr/bin/logall` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/logchan` | `/usr/bin/logchan` | `755` |
| `luci-app-doanduy-modem/root/etc/uci-defaults/99-luci-app-doanduy-modem` | `/etc/uci-defaults/99-luci-app-doanduy-modem` | `755` |
| `luci-app-doanduy-modem/root/usr/share/luci/menu.d/luci-app-doanduy-modem.json` | `/usr/share/luci/menu.d/luci-app-doanduy-modem.json` | `644` |
| `luci-app-doanduy-modem/root/usr/share/rpcd/acl.d/luci-app-doanduy-modem.json` | `/usr/share/rpcd/acl.d/luci-app-doanduy-modem.json` | `644` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/view/modem/control.js` | `/www/luci-static/resources/view/modem/control.js` | `644` |

## Lệnh Kiểm Tra & Triển Khai Riêng Nhóm Này

- **Trên máy tính Windows (PowerShell)**:
  ```powershell
  # Chỉ kiểm tra cú pháp, LF & JSON riêng nhóm 05-adshield-optimizer:
  .\scenarios\05-adshield-optimizer\check.ps1

  # Chỉ đẩy nóng riêng nhóm 05-adshield-optimizer lên Router thật (không đụng 5 nhóm kia):
  .\scenarios\05-adshield-optimizer\deploy.ps1 -Router 192.168.1.1
  ```
- **Trên Linux / Máy chủ Lab / GitHub Actions**:
  ```sh
  sh scenarios/run_scenario.sh check 05-adshield-optimizer
  ```
