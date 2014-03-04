package flixel.tile;
import flixel.FlxObject;
import flixel.system.FlxCollisionType;
import flixel.util.FlxPoint;

/**
 * ...
 * @author Masadow
 */
class FlxBaseTilemap<TilemapKind, TileKind : FlxBaseTile<TilemapKind>> extends FlxObject
{
	/**
	 * No auto-tiling.
	 * Copied from FlxTilemap
	 */
	inline static public var OFF:Int = 0;
	/**
	 * Good for levels with thin walls that don'tile need interior corner art.
	 * Copied from FlxTilemap
	 */
	inline static public var AUTO:Int = 1;
	/**
	 * Better for levels with thick walls that look better with interior corner art.
	 * Copied from FlxTilemap
	 */
	inline static public var ALT:Int = 2;

	/**
	 * Set this flag to use one of the 16-tile binary auto-tile algorithms (OFF, AUTO, or ALT).
	 */
	public var auto:Int;
	/**
	 * Read-only variable, do NOT recommend changing after the map is loaded!
	 */
	public var widthInTiles:Int;
	/**
	 * Read-only variable, do NOT recommend changing after the map is loaded!
	 */
	public var heightInTiles:Int;
	/**
	 * Read-only variable, do NOT recommend changing after the map is loaded!
	 */
	public var totalTiles:Int;
	/**
	 * Internal collection of tile objects, one for each type of tile in the map (NOTE one for every single tile in the whole map).
	 */
	private var _tileObjects:Array<TileKind>;
	/**
	 * Set this to create your own image index remapper, so you can create your own tile layouts.
	 * Mostly useful in combination with the auto-tilers.
	 * 
	 * Normally, each tile's value in _data corresponds to the index of a 
	 * tile frame in the tilesheet. With this active, each value in _data
	 * is a lookup value to that index in customTileRemap.
	 * 
	 * Example:
	 *  customTileRemap = [10,9,8,7,6]
	 *  means: 0=10, 1=9, 2=8, 3=7, 4=6
	 */
	public var customTileRemap:Array<Int> = null;
	/**
	 * If these next two arrays are not null, you're telling FlxTilemap to 
	 * draw random tiles in certain places. 
	 * 
	 * _randomIndices is a list of tilemap values that should be replaced
	 * by a randomly selected value. The available values are chosen from
	 * the corresponding array in randomize_choices
	 * 
	 * So if you have:
	 *   randomIndices = [12,14]
	 *   randomChoices = [[0,1,2],[3,4,5,6,7]]
	 * 
	 * Everywhere the tilemap has a value of 12 it will be replaced by 0, 1, or, 2
	 * Everywhere the tilemap has a value of 14 it will be replaced by 3, 4, 5, 6, 7
	 */
	private var _randomIndices:Array<Int> = null;
	private var _randomChoices:Array<Array<Int>> = null;
	/**
	 * Setting this function allows you to control which choice will be selected for each element within _randomIndices array.
	 * Must return a 0-1 value that gets multiplied by _randomChoices[randIndex].length;
	 */
	private var _randomLambda:Void->Float = null;
	/**
	 * Internal representation of the actual tile data, as a large 1D array of integers.
	 */
	private var _data:Array<Int>;
	/**
	 * Internal, used to sort of insert blank tiles in front of the tiles in the provided graphic.
	 */
	private var _startingIndex:Int;

	/**
	 * Virtual methods, must be implemented in each renderers
	 * This listing should be enhanced with macros
	 */
	private function updateTile(Index:Int):Void {}
	private function cacheGraphics(TileWidth : Int, TileDepth : Int, TileHeight : Int, TileGraphic : Dynamic):Void {}
	private function initTileObjects(DrawIndex : Int, CollideIndex : Int):Void {}
	private function updateMap():Void {}
	public function findPath(Start:FlxPoint, End:FlxPoint, Simplify:Bool = true, RaySimplify:Bool = false, WideDiagonal:Bool = true):Array<FlxPoint> { return null;  }
	private function walkPath(Data:Array<Int>, Start:Int, Points:Array<FlxPoint>):Void {}
	private function computePathDistance(StartIndex:Int, EndIndex:Int, WideDiagonal:Bool):Array<Int> { return null; }
	public function ray(Start:FlxPoint, End:FlxPoint, ?Result:FlxPoint, Resolution:Float = 1):Bool { return false; }
	private function computeDimensions():Void {}

	private function new() 
	{
		super();

		collisionType = FlxCollisionType.TILEMAP;
		
		auto = OFF;
		widthInTiles = 0;
		heightInTiles = 0;
		totalTiles = 0;
		
		// Rendering ?
		immovable = true;
		moves = false;
		cameras = null;
		
		_startingIndex = 0;
	}
	
	/**
	 * Clean up memory.
	 */
	override public function destroy():Void
	{		
		_data = null;

		if (_tileObjects != null)
		{
			l = _tileObjects.length;
			
			for (i in 0...l)
			{
				_tileObjects[i].destroy();
			}
			
			_tileObjects = null;
		}

		super.destroy();
	}

	private function loadMapData(MapData : Dynamic):Void
	{
		// Populate data if MapData is a CSV string
		if (Std.is(MapData, String))
		{
			// Figure out the map dimensions based on the data string
			_data = new Array<Int>();
			var columns:Array<String>;
			var rows:Array<String> = MapData.split("\n");
			heightInTiles = rows.length;
			widthInTiles = 0;
			var row:Int = 0;
			var column:Int;
			
			while (row < heightInTiles)
			{
				columns = rows[row++].split(",");
				
				if (columns.length <= 1)
				{
					heightInTiles = heightInTiles - 1;
					continue;
				}
				if (widthInTiles == 0)
				{
					widthInTiles = columns.length;
				}
				column = 0;
				
				while (column < widthInTiles)
				{
					_data.push(Std.parseInt(columns[column++]));
				}
			}
		}
		// Data is already set up as an Array<Int>
		// DON'T FORGET TO SET 'widthInTiles' and 'heightInTyles' manually BEFORE CALLING loadMap() if you pass an Array<Int>!
		else if (Std.is(MapData, Array))
		{
			_data = MapData;
		}
		else
		{
			throw "Unexpected MapData format '" + Type.typeof(MapData) + "' passed into loadMap. Map data must be CSV string or Array<Int>.";
		}
		
		totalTiles = _data.length;
	}

	private function doAutoTile(DrawIndex : Int, CollideIndex : Int):Void
	{
		// Pre-process the map data if it's auto-tiled
		var i:Int;
		
		if (auto > FlxBaseTilemap.OFF)
		{
			_startingIndex = 1;
			DrawIndex = 1;
			CollideIndex = 1;
			i = 0;
			
			while (i < totalTiles)
			{
				autoTile(i++);
			}
		}
	}

	private function doCustomRemap():Void
	{
		var i:Int = 0;
		
		if (customTileRemap != null) 
		{
			i = 0;
			while ( i < totalTiles) 
			{
				var old_index = _data[i];
				var new_index = old_index;
				if (old_index < customTileRemap.length)
				{
					new_index = customTileRemap[old_index];
				}
				_data[i] = new_index;
				i++;
			}
		}
	}

	private function randomizeIndices():Void
	{
		var i: Int;
		
		if (_randomIndices != null)
		{
			var randLambda:Void->Float = _randomLambda != null ? _randomLambda : Math.random;
			
			i = 0;
			while (i < totalTiles)
			{
				var old_index = _data[i];
				var j = 0;
				var new_index = old_index;
				for (rand in _randomIndices) 
				{
					if (old_index == rand) 
					{
						var k:Int = Std.int(randLambda() * _randomChoices[j].length);
						new_index = _randomChoices[j][k];
					}
					j++;
				}
				_data[i] = new_index;
				i++;
			}
		}
	}

	//Should it be inside rendering ? What should we do about the third dimension parameter ?
	/**
	 * Load the tilemap with string data and a tile graphic.
	 * 
	 * @param	MapData      	A string of comma and line-return delineated indices indicating what order the tiles should go in, or an <code>Array of Int</code>. YOU MUST SET <code>widthInTiles</code> and <code>heightInTyles</code> manually BEFORE CALLING <code>loadMap</code> if you pass an Array!
	 * @param	TileGraphic		All the tiles you want to use, arranged in a strip corresponding to the numbers in MapData.
	 * @param	TileWidth		The width of your tiles (e.g. 8) - defaults to height of the tile graphic if unspecified.
	 * @param	TileDepth		The depth of your tiles (e.g. 8) - defaults to width if unspecified.
	 * @param	TileHeight		The height of your tiles (e.g. 8) - defaults to 0 if unspecified.
	 * @param	AutoTile		Whether to load the map using an automatic tile placement algorithm.  Setting this to either AUTO or ALT will override any values you put for StartingIndex, DrawIndex, or CollideIndex.
	 * @param	StartingIndex	Used to sort of insert empty tiles in front of the provided graphic.  Default is 0, usually safest ot leave it at that.  Ignored if AutoTile is set.
	 * @param	DrawIndex		Initializes all tile objects equal to and after this index as visible. Default value is 1.  Ignored if AutoTile is set.
	 * @param	CollideIndex	Initializes all tile objects equal to and after this index as allowCollisions = ANY.  Default value is 1.  Ignored if AutoTile is set.  Can override and customize per-tile-type collision behavior using <code>setTileProperties()</code>.
	 * @return	A reference to this instance of FlxTilemap, for chaining as usual :)
	 */
	public function loadMap(MapData:Dynamic, TileGraphic:Dynamic, TileWidth:Int = 0, TileDepth:Int = 0, TileHeight:Int = 0, AutoTile:Int = 0, StartingIndex:Int = 0, DrawIndex:Int = 1, CollideIndex:Int = 1):FlxBaseTilemap<TilemapKind, TileKind>
	{
		auto = AutoTile;
		_startingIndex = (StartingIndex <= 0) ? 0 : StartingIndex;

		loadMapData(MapData);
		doAutoTile(DrawIndex, CollideIndex);
		doCustomRemap();
		randomizeIndices();
		cacheGraphics(TileWidth, TileDepth, TileHeight, TileGraphic);
		initTileObjects(DrawIndex, CollideIndex);
		computeDimensions();
		updateMap();

		return this;		
	}

	/**
	 * An internal function used by the binary auto-tilers.
	 * 
	 * @param	Index		The index of the tile you want to analyze.
	 */
	private function autoTile(Index:Int):Void
	{
		if (_data[Index] == 0)
		{
			return;
		}
		
		_data[Index] = 0;
		
		// UP
		if ((Index-widthInTiles < 0) || (_data[Index-widthInTiles] > 0))
		{
			_data[Index] += 1;
		}
		// RIGHT
		if ((Index%widthInTiles >= widthInTiles-1) || (_data[Index+1] > 0))
		{
			_data[Index] += 2;
		}
		// DOWN
		if ((Std.int(Index+widthInTiles) >= totalTiles) || (_data[Index+widthInTiles] > 0)) 
		{
			_data[Index] += 4;
		}
		// LEFT
		if ((Index%widthInTiles <= 0) || (_data[Index-1] > 0))
		{
			_data[Index] += 8;
		}
		
		// The alternate algo checks for interior corners
		if ((auto == FlxBaseTilemap.ALT) && (_data[Index] == 15))
		{
			// BOTTOM LEFT OPEN
			if ((Index%widthInTiles > 0) && (Std.int(Index+widthInTiles) < totalTiles) && (_data[Index+widthInTiles-1] <= 0))
			{
				_data[Index] = 1;
			}
			// TOP LEFT OPEN
			if ((Index%widthInTiles > 0) && (Index-widthInTiles >= 0) && (_data[Index-widthInTiles-1] <= 0))
			{
				_data[Index] = 2;
			}
			// TOP RIGHT OPEN
			if ((Index%widthInTiles < widthInTiles-1) && (Index-widthInTiles >= 0) && (_data[Index-widthInTiles+1] <= 0))
			{
				_data[Index] = 4;
			}
			// BOTTOM RIGHT OPEN
			if ((Index % widthInTiles < widthInTiles - 1) && (Std.int(Index + widthInTiles) < totalTiles) && (_data[Index + widthInTiles + 1] <= 0))
			{
				_data[Index] = 8;
			}
		}
		
		_data[Index] += 1;
	}

	/**
	 * Pathfinding helper function, strips out extra points on the same line.
	 * 
	 * @param	Points		An array of <code>FlxPoint</code> nodes.
	 */
	private function simplifyPath(Points:Array<FlxPoint>):Void
	{
		var deltaPrevious:Float;
		var deltaNext:Float;
		var last:FlxPoint = Points[0];
		var node:FlxPoint;
		var i:Int = 1;
		var l:Int = Points.length - 1;
		
		while(i < l)
		{
			node = Points[i];
			deltaPrevious = (node.x - last.x)/(node.y - last.y);
			deltaNext = (node.x - Points[i + 1].x) / (node.y - Points[i + 1].y);
			
			if ((last.x == Points[i + 1].x) || (last.y == Points[i + 1].y) || (deltaPrevious == deltaNext))
			{
				Points[i] = null;
			}
			else
			{
				last = node;
			}
			
			i++;
		}
	}

	/**
	 * Pathfinding helper function, strips out even more points by raycasting from one point to the next and dropping unnecessary points.
	 * 
	 * @param	Points		An array of <code>FlxPoint</code> nodes.
	 */
	private function raySimplifyPath(Points:Array<FlxPoint>):Void
	{
		var source:FlxPoint = Points[0];
		var lastIndex:Int = -1;
		var node:FlxPoint;
		var i:Int = 1;
		var l:Int = Points.length;
		
		while(i < l)
		{
			node = Points[i++];
			
			if (node == null)
			{
				continue;
			}
			
			if (ray(source,node,_point))	
			{
				if (lastIndex >= 0)
				{
					Points[lastIndex] = null;
				}
			}
			else
			{
				source = Points[lastIndex];
			}
			
			lastIndex = i - 1;
		}
	}

	/**
	 * Adjust collision settings and/or bind a callback function to a range of tiles.
	 * This callback function, if present, is triggered by calls to overlap() or overlapsWithCallback().
	 * 
	 * @param	Tile				The tile or tiles you want to adjust.
	 * @param	AllowCollisions		Modify the tile or tiles to only allow collisions from certain directions, use FlxObject constants NONE, ANY, LEFT, RIGHT, etc.  Default is "ANY".
	 * @param	Callback			The function to trigger, e.g. <code>lavaCallback(Tile:FlxTile, Object:FlxObject)</code>.
	 * @param	CallbackFilter		If you only want the callback to go off for certain classes or objects based on a certain class, set that class here.
	 * @param	Range				If you want this callback to work for a bunch of different tiles, input the range here.  Default value is 1.
	 */
	public function setTileProperties(Tile:Int, AllowCollisions:Int = 0x1111, ?Callback:FlxObject->FlxObject->Void, ?CallbackFilter:Class<Dynamic>, Range:Int = 1):Void
	{
		if (Range <= 0)
		{
			Range = 1;
		}
		
		var tile:TileKind;
		var i:Int = Tile;
		var l:Int = Tile + Range;
		
		while (i < l)
		{
			tile = _tileObjects[i++];
			tile.allowCollisions = AllowCollisions;
			tile.callbackFunction = Callback;
			tile.filter = CallbackFilter;
		}
	}

}