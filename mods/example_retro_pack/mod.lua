-- Reference VFS + Lua hook mod: enables crisp PS1 snap, Bayer dithering & CRT scanlines on any game.
eng.mod.on("post_init", function()
    eng.render.set_retro({ ps1_snap = true, snap_res = 240, dither = true, color_bits = 5, scanlines = 0.22, fog_density = 0.018 })
    eng.log.info("Mod active: example_retro_pack (Amber CRT & PS1 Dither)")
end)
