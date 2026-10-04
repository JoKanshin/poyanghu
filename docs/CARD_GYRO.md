# Unified Card Gyro

The reference is the teammate's enlarged knowledge-card panel in commit
`67e9359` (the gyro was introduced in `5cb16a0`). All card contexts now use that
original rendering path: the panel, illustration and glyphs remain separate
canvas primitives, sharing one parent material and one canvas-space center.
No complete card face is flattened to a four-vertex viewport texture.

`_bind_card_gyro()` binds the reference shader and propagates the parent material
through the card subtree. `_make_gyro_card_view()` puts original panels in fixed
122 x 165 grid controls. Hand selection, live prices, sorting and score animations
continue to operate on the original panels and labels. Detail views create original
panels just like the reference knowledge-card detail.

All contexts use
`_card_gyro_target()` and `_step_card_gyro()` for the same angle limits,
frame-rate-independent damping and transformed center, including return motion.
Grid hover lifts and scales the card once without continuous floating loops.
Hand hover no longer adds a second pointer-driven 2D twist.

## Verification

Run `tests/prepare_visual_test.py card_gyro` to create a project with isolated saves.
Import it with Godot, then run `tests/card_gyro.tscn`. The test checks every gyro
context, rendered pixels, live prices, selection borders, return motion and
small-window framing. It compares the production shader verbatim against
`tests/fixtures/teammate_card_gyro.gdshader`, extracted from the teammate's commit,
and verifies parent-material inheritance throughout every card subtree.
Set `POYANG_SCREENSHOT_DIR` to an existing directory for
rendered screenshots. `tests/knowledge_cards.tscn` covers the 40-card collection
and long knowledge-card names; `tests/visual_smoke.tscn` covers the complete UI flow.
