# Nhóm 02: Quản Lý SIM, Lịch Gia Hạn Tự Động & Hộp Thư SMS (USB & PCIe)

Đọc/gửi/xóa tin nhắn SMS 3GPP Text & UCS-2 PDU đồng bộ trên cả USB và PCIe (Router ME & Thẻ SIM SM), gộp tin nhắn dài, kiểm tra cước 191 và tự động gia hạn gói theo khung giờ vàng.

## Danh Sách Kịch Bản Độc Lập Trong Nhóm Này

> Khi nâng cấp hoặc sửa lỗi nhóm `02-sim-sms`, **chỉ chỉnh sửa các tệp trong bảng dưới đây**, tuyệt đối không tác động sang 5 nhóm còn lại.

| Đường dẫn trong GitHub Repo | Đường dẫn trên Router OpenWrt | Quyền |
| :--- | :--- | :---: |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/luci.sms-status` | `/usr/libexec/rpcd/luci.sms-status` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/read_pcie_sms.lua` | `/usr/bin/read_pcie_sms.lua` | `755` |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/doanduy.sim` | `/usr/libexec/rpcd/doanduy.sim` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/daily_vip_renew.sh` | `/usr/bin/daily_vip_renew.sh` | `755` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/doanduy/tab_sms.js` | `/www/luci-static/resources/doanduy/tab_sms.js` | `644` |

## Lệnh Kiểm Tra & Triển Khai Riêng Nhóm Này

- **Trên máy tính Windows (PowerShell)**:
  ```powershell
  # Chỉ kiểm tra cú pháp, LF & JSON riêng nhóm 02-sim-sms:
  .\scenarios\02-sim-sms\check.ps1

  # Chỉ đẩy nóng riêng nhóm 02-sim-sms lên Router thật (không đụng 5 nhóm kia):
  .\scenarios\02-sim-sms\deploy.ps1 -Router 192.168.1.1
  ```
- **Trên Linux / Máy chủ Lab / GitHub Actions**:
  ```sh
  sh scenarios/run_scenario.sh check 02-sim-sms
  ```
