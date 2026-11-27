# 🌐 Nhóm 07: Auto-Mesh Đa Chip Tự Động (`07-auto-mesh`)

Tự động ghép Mesh WDS xuyên nền tảng chip (Qualcomm IPQ60xx/IPQ807x NSS & Mainline, MediaTek Filogic MT7981/MT7986 `mt76` & `mt_wifi`):

1. **Khi khởi động CÓ MẠNG gốc (5G WWAN hoặc WAN dây):** Thiết bị tự nhận vai **Router Chính (`192.168.1.1`)**, bật DHCP và phát sóng Backhaul WDS `DOANDUY_MESH`.
2. **Khi khởi động KHÔNG CÓ MẠNG gốc:** Thiết bị quét thấy sóng `DOANDUY_MESH` sẽ tự nhận vai **Router Phụ**, tự đổi IP sang `192.168.1.10` (nếu trùng tự tăng `.11`, `.12`), tắt DHCP, khóa kênh theo Router Chính và bắc cầu WDS trong suốt.
3. **Khi hết Mesh (tắt Router Chính >= 30s hoặc bấm Tắt Mesh):** Thiết bị tự động xóa `mesh_sta`, khôi phục IP mặc định `192.168.1.1` và bật lại DHCP.
