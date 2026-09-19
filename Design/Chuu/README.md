# Chuu icon

Editable source: `../../Resources/Chuu.icon`.

Three original SVG layers: pearl mouse shell, recessed button divisions, and a mint battery/scroll wheel. SVGs contain only geometry and flat colors; Icon Composer supplies the specular highlights, refraction, translucency, and shadows. The 14-degree tilt keeps the mouse recognizable without tying it to a hardware brand.

Default uses a pale gray-green base and pearl shell. Dark uses the system dark base plus explicit shell, seam and wheel color overrides. The source was opened, adjusted and saved in Xcode's Icon Composer. `ictool` exports are rendered by Apple's icon pipeline, not flat imitations of Liquid Glass.

The app consumes the `.icon` document directly through Xcode. Preview PNGs are for review only. Internal application identifiers remain unchanged by the Chuu name.

Verified: Icon Composer Default, Dark and Mono previews; Apple-rendered 64 px Default/Dark previews; Debug and Release builds; installed app's About panel showing Chuu and its new icon; deep strict signature verification. No mouse protocol, profile or input-processing behavior changed as part of the icon work.
