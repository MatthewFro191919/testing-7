package objects;

import backend.animation.PsychAnimationController;
import flixel.util.FlxSort;
import flixel.util.FlxDestroyUtil;
import flixel.system.FlxAssets;
import openfl.display.BitmapData;
import openfl.display.PNGEncoderOptions;
import openfl.utils.ByteArray;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import openfl.geom.Rectangle;
import haxe.Json;
import backend.Song;
import states.stages.objects.TankmenBG;

typedef CharacterFile = {
	var animations:Array<AnimArray>;
	var image:String;
	var scale:Float;
	var sing_duration:Float;
	var healthicon:String;

	var position:Array<Float>;
	var camera_position:Array<Float>;
	var flip_x:Bool;
	var no_antialiasing:Bool;
	var healthbar_colors:Array<Int>;
	var vocals_file:String;
	@:optional var _editor_isPlayer:Null<Bool>;
}

typedef AnimArray = {
	var anim:String;
	var name:String;
	var fps:Int;
	var loop:Bool;
	var indices:Array<Int>;
	var offsets:Array<Int>;
}

class Character extends FlxSprite {
	/**
	 * In case a character is missing, it will use this on its place
	**/
	public static final DEFAULT_CHARACTER:String = 'bf';

	public var animOffsets:Map<String, Array<Dynamic>>;
	public var debugMode:Bool = false;
	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public var isPlayer:Bool = false;
	public var curCharacter:String = DEFAULT_CHARACTER;

	public var holdTimer:Float = 0;
	public var heyTimer:Float = 0;
	public var specialAnim:Bool = false;
	public var animationNotes:Array<Dynamic> = [];
	public var stunned:Bool = false;
	public var singDuration:Float = 4; // Multiplier of how long a character holds the sing pose
	public var idleSuffix:String = '';
	public var danceIdle:Bool = false; // Character use "danceLeft" and "danceRight" instead of "idle"
	public var skipDance:Bool = false;

	public var healthIcon:String = 'face';
	public var animationsArray:Array<AnimArray> = [];

	public var positionArray:Array<Float> = [0, 0];
	public var cameraPosition:Array<Float> = [0, 0];
	public var healthColorArray:Array<Int> = [255, 0, 0];

	public var missingCharacter:Bool = false;
	public var missingText:FlxText;
	public var hasMissAnimations:Bool = false;
	public var vocalsFile:String = '';

	// Used on Character Editor
	public var imageFile:String = '';
	public var jsonScale:Float = 1;
	public var noAntialiasing:Bool = false;
	public var originalFlipX:Bool = false;
	public var editorIsPlayer:Null<Bool> = null;

	public var danced:Bool = false;
	public var danceEveryNumBeats:Int = 2;
	private var settingCharacterUp:Bool = true;

	// Atlas support
	@:allow(states.editors.CharacterEditorState)
	public var isAnimateAtlas(default, null):Bool = false;
	#if flxanimate
	public var atlas:FlxAnimate;
	#end

	public function new(x:Float, y:Float, ?character:String = 'bf', ?isPlayer:Bool = false) {
		super(x, y);

		animation = new PsychAnimationController(this);

		animOffsets = new Map<String, Array<Dynamic>>();
		this.isPlayer = isPlayer;
		changeCharacter(character);

		switch (curCharacter) {
			case 'pico-speaker':
				skipDance = true;
				loadMappedAnims();
				playAnim("shoot1");
			case 'pico-blazin', 'darnell-blazin':
				skipDance = true;
		}
	}

	public function changeCharacter(character:String) {
		animationsArray = [];
		animOffsets = new Map<String, Array<Dynamic>>();
		curCharacter = character;
		var characterPath:String = 'characters/$character.json';

		var path:String = Paths.getPath(characterPath, TEXT);
		#if MODS_ALLOWED
		if (!FileSystem.exists(path))
		#else
		if (!Assets.exists(path))
		#end
		{
			path = Paths.getSharedPath('characters/' + DEFAULT_CHARACTER +
				'.json'); // If a character couldn't be found, change him to BF just to prevent a crash
			missingCharacter = true;
			missingText = new FlxText(0, 0, 300, 'ERROR:\n$character.json', 16);
			missingText.alignment = CENTER;
		}

		try {
			#if MODS_ALLOWED
			loadCharacterFile(Json.parse(File.getContent(path)));
			#else
			loadCharacterFile(Json.parse(Assets.getText(path)));
			#end
		} catch (e:Dynamic) {
			trace('Error loading character file of "$character": $e');
		}

		skipDance = false;
		hasMissAnimations = hasAnimation('singLEFTmiss') || hasAnimation('singDOWNmiss') || hasAnimation('singUPmiss') || hasAnimation('singRIGHTmiss');
		recalculateDanceIdle();
		dance();
	}

	public function loadCharacterFile(json:Dynamic) {
		isAnimateAtlas = false;

		#if flxanimate
		var animToFind:String = Paths.getPath('images/' + json.image + '/Animation.json', TEXT);
		if (#if MODS_ALLOWED FileSystem.exists(animToFind) || #end Assets.exists(animToFind))
			isAnimateAtlas = true;
		#end

		scale.set(1, 1);
		updateHitbox();

		if (!isAnimateAtlas) {
			frames = Paths.getMultiAtlas(json.image.split(','));
		}
		#if flxanimate
		else {
			atlas = new FlxAnimate();
			atlas.showPivot = false;
			try {
				Paths.loadAnimateAtlas(atlas, json.image);
			} catch (e:haxe.Exception) {
				FlxG.log.warn('Could not load atlas ${json.image}: $e');
				trace(e.stack);
			}
		}
		#end

		imageFile = json.image;
		jsonScale = json.scale;
		if (json.scale != 1) {
			scale.set(jsonScale, jsonScale);
			updateHitbox();
		}

		// positioning
		positionArray = json.position;
		cameraPosition = json.camera_position;

		// data
		healthIcon = json.healthicon;
		singDuration = json.sing_duration;
		flipX = (json.flip_x != isPlayer);
		healthColorArray = (json.healthbar_colors != null && json.healthbar_colors.length > 2) ? json.healthbar_colors : [161, 161, 161];
		vocalsFile = json.vocals_file != null ? json.vocals_file : '';
		originalFlipX = (json.flip_x == true);
		editorIsPlayer = json._editor_isPlayer;

		// antialiasing
		noAntialiasing = (json.no_antialiasing == true);
		antialiasing = ClientPrefs.data.antialiasing ? !noAntialiasing : false;

		// animations
		animationsArray = json.animations;
		if (animationsArray != null && animationsArray.length > 0) {
			for (anim in animationsArray) {
				var animAnim:String = '' + anim.anim;
				var animName:String = '' + anim.name;
				var animFps:Int = anim.fps;
				var animLoop:Bool = !!anim.loop; // Bruh
				var animIndices:Array<Int> = anim.indices;

				if (!isAnimateAtlas) {
					if (animIndices != null && animIndices.length > 0)
						animation.addByIndices(animAnim, animName, animIndices, "", animFps, animLoop);
					else
						animation.addByPrefix(animAnim, animName, animFps, animLoop);
				}
				#if flxanimate
				else {
					if (animIndices != null && animIndices.length > 0)
						atlas.anim.addBySymbolIndices(animAnim, animName, animIndices, animFps, animLoop);
					else
						atlas.anim.addBySymbol(animAnim, animName, animFps, animLoop);
				}
				#end

				if (anim.offsets != null && anim.offsets.length > 1)
					addOffset(anim.anim, anim.offsets[0], anim.offsets[1]);
				else
					addOffset(anim.anim, 0, 0);
			}
			#if flxanimate
			if (isAnimateAtlas)
				copyAtlasValues();
			#end
			// trace('Loaded file to character ' + curCharacter);
		}
	}

	override function update(elapsed:Float) {
		#if flxanimate
		if (isAnimateAtlas)
			atlas.update(elapsed);
		#end

		if (debugMode
			|| (!isAnimateAtlas && animation.curAnim == null)
			|| (#if flxanimate isAnimateAtlas && (atlas.anim.curInstance == null || atlas.anim.curSymbol == null) #else false #end)) {
			super.update(elapsed);
			return;
		}

		if (heyTimer > 0) {
			var rate:Float = (PlayState.instance != null ? PlayState.instance.playbackRate : 1.0);
			heyTimer -= elapsed * rate;
			if (heyTimer <= 0) {
				var anim:String = getAnimationName();
				if (specialAnim && (anim == 'hey' || anim == 'cheer')) {
					specialAnim = false;
					dance();
				}
				heyTimer = 0;
			}
		} else if (specialAnim && isAnimationFinished()) {
			specialAnim = false;
			dance();
		} else if (getAnimationName().endsWith('miss') && isAnimationFinished()) {
			dance();
			finishAnimation();
		}

		switch (curCharacter) {
			case 'pico-speaker':
				if (animationNotes.length > 0 && Conductor.songPosition > animationNotes[0][0]) {
					var noteData:Int = 1;
					if (animationNotes[0][1] > 2)
						noteData = 3;

					noteData += FlxG.random.int(0, 1);
					playAnim('shoot' + noteData, true);
					animationNotes.shift();
				}
				if (isAnimationFinished())
					playAnim(getAnimationName(), false, false, animation.curAnim.frames.length - 3);
		}

		if (getAnimationName().startsWith('sing'))
			holdTimer += elapsed;
		else if (isPlayer)
			holdTimer = 0;

		if (!isPlayer
			&& holdTimer >= Conductor.stepCrochet * (0.0011 #if FLX_PITCH / (FlxG.sound.music != null ? FlxG.sound.music.pitch : 1) #end) * singDuration) {
			dance();
			holdTimer = 0;
		}

		var name:String = getAnimationName();
		if (isAnimationFinished() && hasAnimation('$name-loop'))
			playAnim('$name-loop');

		super.update(elapsed);
	}

	var _lastPlayedAnimation:String;

	inline public function isAnimationNull():Bool {
		return !isAnimateAtlas ? (animation.curAnim == null) : (#if flxanimate (atlas.anim.curInstance == null || atlas.anim.curSymbol == null) #else true #end);
	}

	inline public function getAnimationName():String {
		return _lastPlayedAnimation;
	}

	public function isAnimationFinished():Bool {
		if (isAnimationNull())
			return false;
		return !isAnimateAtlas ? animation.curAnim.finished : (#if flxanimate atlas.anim.finished #else false #end);
	}

	public function finishAnimation():Void {
		if (isAnimationNull())
			return;

		if (!isAnimateAtlas)
			animation.curAnim.finish();
		#if flxanimate
		else
			atlas.anim.curFrame = atlas.anim.length - 1;
		#end
	}

	public function hasAnimation(anim:String):Bool {
		return animOffsets.exists(anim);
	}

	public var animPaused(get, set):Bool;

	private function get_animPaused():Bool {
		if (isAnimationNull())
			return false;
		return !isAnimateAtlas ? animation.curAnim.paused : (#if flxanimate atlas.anim.isPlaying #else false #end);
	}

	private function set_animPaused(value:Bool):Bool {
		if (isAnimationNull())
			return value;
		if (!isAnimateAtlas)
			animation.curAnim.paused = value;
		#if flxanimate
		else {
			if (value)
				atlas.pauseAnimation();
			else
				atlas.resumeAnimation();
		}
		#end

		return value;
	}

	/**
	 * FOR GF DANCING SHIT
	 */
	public function dance() {
		if (!debugMode && !skipDance && !specialAnim) {
			if (danceIdle) {
				danced = !danced;
				if (danced)
					playAnim('danceRight' + idleSuffix);
				else
					playAnim('danceLeft' + idleSuffix);
			} else if (hasAnimation('idle' + idleSuffix))
				playAnim('idle' + idleSuffix);
		}
	}

	public function playAnim(AnimName:String, Force:Bool = false, Reversed:Bool = false, Frame:Int = 0):Void {
		specialAnim = false;
		if (!isAnimateAtlas) {
			animation.play(AnimName, Force, Reversed, Frame);
		} 
		#if flxanimate
		else {
			atlas.anim.play(AnimName, Force, Reversed, Frame);
			atlas.update(0);
		}
		#end
		_lastPlayedAnimation = AnimName;

		if (hasAnimation(AnimName)) {
			var daOffset = animOffsets.get(AnimName);
			offset.set(daOffset[0], daOffset[1]);
		}
		// else offset.set(0, 0);

		if (curCharacter.startsWith('gf-') || curCharacter == 'gf') {
			if (AnimName == 'singLEFT')
				danced = true;
			else if (AnimName == 'singRIGHT')
				danced = false;

			if (AnimName == 'singUP' || AnimName == 'singDOWN')
				danced = !danced;
		}
	}

	public function exportFramesTo(folder:String):Void {
		if (animation == null) {
			return;
		}

		for (animName in animation.getNameList()) {
			var anim = animation.getByName(animName);
			if (anim == null)
				continue;

			playAnim(animName, true);

			for (i in 0...anim.frames.length) {
				var frameIndex = anim.frames[i];
				var frame = frames.frames[frameIndex];
				if (frame == null)
					continue;

				var rect = new openfl.geom.Rectangle(Std.int(frame.frame.x), Std.int(frame.frame.y), Std.int(frame.frame.width),
					Std.int(frame.frame.height));

				var bmp = new BitmapData(Std.int(rect.width), Std.int(rect.height), true, 0x00000000);
				bmp.draw(graphic.bitmap, null, null, null, rect, true);

				var byteArray = bmp.encode(bmp.rect, new PNGEncoderOptions());
				var paddedIndex = StringTools.lpad(i + "", "0", 4);
				var path = folder + '/' + animName + paddedIndex + '.png';
				saveBytes(path, byteArray);
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

	function loadMappedAnims():Void {
		try {
			var songData:SwagSong = Song.getChart('picospeaker', Paths.formatToSongPath(Song.loadedSongName));
			if (songData != null)
				for (section in songData.notes)
					for (songNotes in section.sectionNotes)
						animationNotes.push(songNotes);

			TankmenBG.animationNotes = animationNotes;
			animationNotes.sort(sortAnims);
		} catch (e:Dynamic) {}
	}

	function sortAnims(Obj1:Array<Dynamic>, Obj2:Array<Dynamic>):Int {
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1[0], Obj2[0]);
	}

	public function recalculateDanceIdle() {
		var lastDanceIdle:Bool = danceIdle;
		danceIdle = (hasAnimation('danceLeft' + idleSuffix) && hasAnimation('danceRight' + idleSuffix));

		if (settingCharacterUp) {
			danceEveryNumBeats = (danceIdle ? 1 : 2);
		} else if (lastDanceIdle != danceIdle) {
			var calc:Float = danceEveryNumBeats;
			if (danceIdle)
				calc /= 2;
			else
				calc *= 2;

			danceEveryNumBeats = Math.round(Math.max(calc, 1));
		}
		settingCharacterUp = false;
	}

	public function addOffset(name:String, x:Float = 0, y:Float = 0) {
		animOffsets[name] = [x, y];
	}

	public function quickAnimAdd(name:String, anim:String) {
		animation.addByPrefix(name, anim, 24, false);
	}

	#if flxanimate
	public override function draw() {
		var lastAlpha:Float = alpha;
		var lastColor:FlxColor = color;
		if (missingCharacter) {
			alpha *= 0.6;
			color = FlxColor.BLACK;
		}

		if (isAnimateAtlas) {
			if (atlas.anim.curInstance != null) {
				copyAtlasValues();
				atlas.draw();
				alpha = lastAlpha;
				color = lastColor;
				if (missingCharacter && visible) {
					missingText.x = getMidpoint().x - 150;
					missingText.y = getMidpoint().y - 10;
					missingText.draw();
				}
			}
			return;
		}
		super.draw();
		if (missingCharacter && visible) {
			alpha = lastAlpha;
			color = lastColor;
			missingText.x = getMidpoint().x - 150;
			missingText.y = getMidpoint().y - 10;
			missingText.draw();
		}
	}

	public function copyAtlasValues() {
		@:privateAccess
		{
			atlas.cameras = cameras;
			atlas.scrollFactor = scrollFactor;
			atlas.scale = scale;
			atlas.offset = offset;
			atlas.origin = origin;
			atlas.x = x;
			atlas.y = y;
			atlas.angle = angle;
			atlas.alpha = alpha;
			atlas.visible = visible;
			atlas.flipX = flipX;
			atlas.flipY = flipY;
			atlas.shader = shader;
			atlas.antialiasing = antialiasing;
			atlas.colorTransform = colorTransform;
			atlas.color = color;
		}
	}

	public override function destroy() {
		atlas = FlxDestroyUtil.destroy(atlas);
		super.destroy();
	}
	#else
	public override function draw() {
		var lastAlpha:Float = alpha;
		var lastColor:FlxColor = color;
		if (missingCharacter) {
			alpha *= 0.6;
			color = FlxColor.BLACK;
		}

		super.draw();
		if (missingCharacter && visible) {
			alpha = lastAlpha;
			color = lastColor;
			missingText.x = getMidpoint().x - 150;
			missingText.y = getMidpoint().y - 10;
			missingText.draw();
		}
	}
	#end
}
