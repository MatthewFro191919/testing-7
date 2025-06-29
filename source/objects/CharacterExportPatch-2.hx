
import flixel.system.FlxAssets;
import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;
import openfl.utils.ByteArray;

public function exportFrames(character:String):Void {
    if (animation == null || animation.curAnim == null) return;

    var exportDir = 'exported_frame/' + character + '/frames/';
    trace('Exporting frames to: ' + exportDir);
    var animList = animation.animations;

    for (anim in animList) {
        var animName = anim.name;
        var animFrames = anim.frames;

        for (i in 0...animFrames.length) {
            var frame = animFrames[i];
            var bitmapData:BitmapData = new BitmapData(frame.frame.width, frame.frame.height, true, 0x00000000);
            bitmapData.draw(graphic, null, null, null, frame.frame, true);

            var byteArray = bitmapData.encode(bitmapData.rect, new PNGEncoderOptions());
            var paddedIndex = StringTools.lpad(i + "", "0", 4); // e.g., 0001
            var filePath = exportDir + animName + paddedIndex + '.png';
            saveBytes(filePath, byteArray);
        }
    }
}

public static function saveBytes(filePath:String, data:ByteArray):Void {
    #if sys
    var file = sys.io.File.write(filePath, true);
    file.write(data);
    file.close();
    #end
}
