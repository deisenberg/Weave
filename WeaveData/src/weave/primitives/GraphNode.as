package weave.primitives
{
	import flash.geom.Point;
	
	import weave.api.primitives.IBounds2D;

	public class GraphNode
	{
		public function GraphNode()
		{
		}
		
		public var id:int;
		public var value:Object;
		public var label:String;
		
		public var isDrawn:Boolean = false;
		public var velocity:Point = new Point();
		private var _position:Point = new Point();
		public function get position():Point 
		{ 
			return _position; 
		}
		public function set position(p:Point):void
		{
			bounds.reset();
			bounds.includePoint(p);
			_position.x = p.x;
			_position.y = p.y;
		}
		public function set x(__x:Number):void { _position.x = __x; }
		public function get x():Number { return _position.x; }
		public function set y(__y:Number):void { _position.y = __y; }
		public function get y():Number { return _position.y; }
		public var bounds:IBounds2D = new Bounds2D();
		public var nextPosition:Point = new Point();
	}
}