# ColorSwitcher (better name pending)

This small macOS application allows changing the color that Nintendo Switch
Joy-Cons and Pro Controllers report to the console.

Use it after replacing your Joy-Cons shells or Pro Controller grips to make the
Switch aware of their new colors.

## Usage

1. Pair your controllers to your Mac using Bluetooth: Open System Settings >
   Bluetooth, and press the pair button on your controller. When the controller
   shows up in the Bluetooth preferences, press Connect. (Once you physically
   re-pair the controllers to the Switch, you will need to delete them from
   the Bluetooth preferences by second-clicking on them and choosing Forget)
2. Run ColorSwitcher and click Refresh. Select a the controller you want to
   edit in the drop-down list and click Get Colors to retrieve its current
   colors.
3. Edit the colors by clicking on them. Use the preview to get an idea of how
   the colors will look like on the Switch. Once you are done, click Set Colors
   to write them to the controller.
4. If you want to apply the same colors to another controller, select it in the
   drop-down list and click Set Colors.

### Pro Controller colors

The ability of Pro Controllers to have grip colors distinct from their main
body was not present on the Switch release and was introduced later (possibly
with Switch firmware 5.0). Since older controllers did not have grip color data,
the Switch only takes the grip colors into account if a specific byte is set to
2 in the controller data. This byte is 1 (or 0?) on older controllers, which
will prevent the grip colors from being displayed on the Switch.

Fortunately, ColorSwitch is able to detect this situation, and will
automatically allow you to set the controller data byte to 2 when necessary.

## Build

Use the Xcode project to build ColorSwitcher.

By default, the application will be signed for local run only; if you want to
sign it with your development team ID, create a `local.xcconfig` file in the
same directory as this README file, with the following contents:

```
DEVELOPMENT_TEAM = <team id, without quotes>
```

You can also put other Xcode configuration values in this file.


## TODO

- [ ] Create an icon
- [ ] Nicer controller preview (use Bézier curves to draw the Pro Controller)
- [ ] Better GUI layout
- [ ] Auto-refresh the controller list
- [ ] Port the application to Windows and Linux — the application backend
      (`ControllerManager`) should work on any system supported by both Swift
      and `hidapi`, but the GUI front-end will need to be written with another
      framework (GTK?).
