-- vm — the QEMU guest (nixosConfigurations.vm). One virtio-gpu, one card; let Hyprland pick both.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
hl.workspace_rule({ workspace = "1", persistent = true, default = true })

-- virtio-gpu has no hardware cursor plane; without this the pointer is invisible.
hl.config({ cursor = { no_hardware_cursors = true } })
