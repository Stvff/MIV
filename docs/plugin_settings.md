## Plugin Settings API
A plugin can optionally enable the ability to declare its own settings by setting the `has_settings` field in
`Provided_Registration_Entry` to true.\
If this flag is set to true, a function with the following signature has to be defined (with the established naming scheme):
```c
string settings(Pre_Rendering_Info *pre_info, Rendering_Info *render_info, Settings_Info *settings_info);
```
The `settings()` function gets called whenever the settings menu is opened in MIV, as well as when a plugin setting has changed (in that menu).
This function takes the known `Pre_Rendering_Info` and `Rendering_Info` parameters, but also takes `Settings_Info`.

The `changed_index` is the primary indicator of the situation under which MIV called the `settings()` function.
If it is `-1`, then the settings menu was just opened, and the plugin is expected to populate the relevant fields of `Settings_Info`.
