# Godot Weather System

Weather for Godot 4: rain around the camera, lightning and thunder, wet puddles, and rain kept
out of where it does not fall.

## Features

* `WeatherNode` - the weather of a scene: precipitation, cloud density, overcast, storm and its fog,
  wind; signals for a game to follow it (`thunder`, `rain_strength_changed`,
  `rain_local_strength_changed`, `wind_changed`)
* rain as GPU streaks in near and mid layers following the camera, driven by the wind
* lightning flashes and thunder in a storm
* `RainVolume` - a box where the rain is taken away (under a roof, in a tunnel) or changed, with a
  feathered edge; the rain shader culls it per frame
* `PuddleSurface3D` - puddles on a mask, getting wet with the rain, with ripples and refraction
* drives a sky (`skydome_path`, such as [Godot Skydome](https://github.com/GamesNotDeveloped/godot-skydome))
  and a `WorldEnvironment`
* the rain's look in the project settings (`gnd_weather/*`) for every `WeatherNode` with
  `apply_project_settings`
* editor views of the weather probes and the rain meshes

## Usage

* Enable the plugin
* Add a `WeatherNode` to the 3D scene and set its paths to the sky and the `WorldEnvironment`
* Set its precipitation, clouds and storm, by hand or from a game's weather
* Add `RainVolume` nodes where the rain should not fall
