# 3D models

Every model in the game is our own. Until 0.10.x the props came from poly.pizza (Patrick's picks),
the Quaternius Ultimate House Interior pack, Poly Haven and a roulette wheel file; those files were
used only as a reference for role, size and silhouette, rebuilt from scratch in our warm low-poly
casino style (docs/ART_DIRECTION.md) and then deleted, so nothing in the build needs a third-party
licence or attribution for its models.

## How they are made

- `tools/models/model_kit.gd` (`ModelKit`): turned (lathe) profiles, bevelled extrusions, swept
  tubes and primitive parts, merged into one mesh with one surface per named material.
- `tools/models/prop_recipes.gd` (`PropRecipes`): one recipe per model, in metres, y up, standing
  on y = 0, front facing +z (the statues and the bat/revolver keep the orientation the game code
  expects; see each recipe's comment).
- `tools/models/make_textures.py`: paints the picture-frame painting and the roulette number ring.
- `tools/models/build_models.gd`: writes every recipe to `assets/models/own/<id>.glb`.
- `tools/models/render_models.gd`: look-dev renders of model files from three angles.

Rebuild after changing a recipe:

```
python3 tools/models/make_textures.py            # only if the textures changed
tools/godot/godot --headless --path . -s tools/models/build_models.gd -- [--only id,id]
tools/godot/godot --headless --path . --import
```

Material names are part of the contract: `LoungeDecor._recolor` swaps materials by name
("Marble" on columns and pedestals, "White"/"Glass" on windows, "Fabric"/"Gold" on curtains,
"Wood"/"Gold" on doors).

## Where they are used

| File (`assets/models/own/`) | Game id | Used by | Replaced |
|---|---|---|---|
| poker_chip.glb | `PropModels` poker_chip | chip piles on the floor | poly.pizza poker chip |
| money_pile.glb | money_pile | cash heaps by Peg Drop when the jackpot is big | poly.pizza money pile |
| bar_stool.glb | seat | every seat at the games, Last Seat | poly.pizza bar stool |
| couch.glb | couch | start room, parlor, vault | poly.pizza couch |
| plant_palm.glb, plant_bush.glb, plant_spiky.glb | plant_1..3 | lobby and floor plants | poly.pizza flowers 1-3 |
| cone.glb | cone | games that are out of order | poly.pizza cone |
| beer_mug_empty.glb | beer | the empty bottle item | poly.pizza beer mug |
| column.glb, pedestal.glb | column, pedestal | lounge pillars, parlor, vault; statue pedestals | Quaternius columns |
| window_arch.glb, curtains.glb, door_double.glb | window_arch, curtains, door_double | lounge walls | Quaternius window, curtains, doors |
| picture.glb, mirror.glb | picture, mirror | lounge and parlor walls | Poly Haven frame and mirror |
| bust.glb, horse.glb | bust, horse | VIP lounge statues (also on the website) | Poly Haven bust and horse |
| coin.glb | `ItemModels.DEFAULT_MODEL` | items without a model of their own | poly.pizza coin |
| bat.glb, revolver.glb, beer_mug_full.glb | `ItemModels.MODELS` | baseball bat, russian roulette, beer | poly.pizza bat, revolver, beer |
| roulette_wheel.glb (+ textures/roulette_ring.png) | `RouletteStation.WHEEL_MODEL` | the roulette wheel; its "Rotor" part turns | the Rolley roulette wheel |

The other items are hand-built at runtime by `items/item_art.gd`.
