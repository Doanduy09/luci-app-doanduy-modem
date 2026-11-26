# Nhóm 06: Nhà Thông Minh Tự Nhận Diện IP, Thiết Bị Vô Hạn, S06 IR & Voice ESP32

Tự động nhận diện thiết bị thông minh khi dán IP hoặc quét mạng LAN (WLED, Shelly, Tasmota, Yeelight, Sonoff DIY, Tuya 6668, Camera RTSP, Android TV, Soundbar), hỗ trợ không giới hạn loại thiết bị & nút lệnh.

## Danh Sách Kịch Bản Độc Lập Trong Nhóm Này

> Khi nâng cấp hoặc sửa lỗi nhóm `06-smarthome`, **chỉ chỉnh sửa các tệp trong bảng dưới đây**, tuyệt đối không tác động sang 5 nhóm còn lại.

| Đường dẫn trong GitHub Repo | Đường dẫn trên Router OpenWrt | Quyền |
| :--- | :--- | :---: |
| `luci-app-doanduy-modem/root/usr/libexec/rpcd/doanduy.smarthome` | `/usr/libexec/rpcd/doanduy.smarthome` | `755` |
| `luci-app-doanduy-modem/root/usr/lib/lua/doanduy/smarthome/net_json.lua` | `/usr/lib/lua/doanduy/smarthome/net_json.lua` | `644` |
| `luci-app-doanduy-modem/root/usr/lib/lua/doanduy/smarthome/store.lua` | `/usr/lib/lua/doanduy/smarthome/store.lua` | `644` |
| `luci-app-doanduy-modem/root/usr/lib/lua/doanduy/smarthome/catalog.lua` | `/usr/lib/lua/doanduy/smarthome/catalog.lua` | `644` |
| `luci-app-doanduy-modem/root/usr/lib/lua/doanduy/smarthome/discovery.lua` | `/usr/lib/lua/doanduy/smarthome/discovery.lua` | `644` |
| `luci-app-doanduy-modem/root/usr/lib/lua/doanduy/smarthome/drivers.lua` | `/usr/lib/lua/doanduy/smarthome/drivers.lua` | `644` |
| `luci-app-doanduy-modem/root/usr/lib/lua/tuya_v35_local.lua` | `/usr/lib/lua/tuya_v35_local.lua` | `644` |
| `luci-app-doanduy-modem/root/usr/lib/lua/ac_ir_protocols.lua` | `/usr/lib/lua/ac_ir_protocols.lua` | `644` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/doanduy/smarthome_modal.js` | `/www/luci-static/resources/doanduy/smarthome_modal.js` | `644` |
| `luci-app-doanduy-modem/htdocs/luci-static/resources/doanduy/smarthome.js` | `/www/luci-static/resources/doanduy/smarthome.js` | `644` |

## Lệnh Kiểm Tra & Triển Khai Riêng Nhóm Này

- **Trên máy tính Windows (PowerShell)**:
  ```powershell
  # Chỉ kiểm tra cú pháp, LF & JSON riêng nhóm 06-smarthome:
  .\scenarios\06-smarthome\check.ps1

  # Chỉ đẩy nóng riêng nhóm 06-smarthome lên Router thật (không đụng 5 nhóm kia):
  .\scenarios\06-smarthome\deploy.ps1 -Router 192.168.1.1
  ```
- **Trên Linux / Máy chủ Lab / GitHub Actions**:
  ```sh
  sh scenarios/run_scenario.sh check 06-smarthome
  ```
