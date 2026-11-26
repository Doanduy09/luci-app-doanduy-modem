# Nhóm 03: Modem 5G, Khóa Băng Tần, Khóa Trạm BTS, IMEI Luhn & TTL

Điều khiển sóng 4G/5G (Band Lock tự động theo nhà mạng hoặc chọn tay từng band, Cell Lock), kiểm định Luhn 15 số trước khi đổi IMEI, đổi TTL=65 chống bóp băng thông và trạng thái tổng quan LuCI.

## Danh Sách Kịch Bản Độc Lập Trong Nhóm Này

> Khi nâng cấp hoặc sửa lỗi nhóm `03-rf-band-imei`, **chỉ chỉnh sửa các tệp trong bảng dưới đây**, tuyệt đối không tác động sang 5 nhóm còn lại.

| Đường dẫn trong GitHub Repo | Đường dẫn trên Router OpenWrt | Quyền |
| :--- | :--- | :---: |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/doanduy.rf` | `/usr/libexec/rpcd/doanduy.rf` | `755` |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/modem_ctrl` | `/usr/libexec/rpcd/modem_ctrl` | `755` |
| `luci-app-doanduy-modem/root/usr/bin/imei` | `/usr/bin/imei` | `755` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/doanduy/tab_modem.js` | `/www/luci-static/resources/doanduy/tab_modem.js` | `644` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/view/status/include/11_modem.js` | `/www/luci-static/resources/view/status/include/11_modem.js` | `644` |

## Lệnh Kiểm Tra & Triển Khai Riêng Nhóm Này

- **Trên máy tính Windows (PowerShell)**:
  ```powershell
  # Chỉ kiểm tra cú pháp, LF & JSON riêng nhóm 03-rf-band-imei:
  .\scenarios\03-rf-band-imei\check.ps1

  # Chỉ đẩy nóng riêng nhóm 03-rf-band-imei lên Router thật (không đụng 5 nhóm kia):
  .\scenarios\03-rf-band-imei\deploy.ps1 -Router 192.168.1.1
  ```
- **Trên Linux / Máy chủ Lab / GitHub Actions**:
  ```sh
  sh scenarios/run_scenario.sh check 03-rf-band-imei
  ```
