package weave.primitives
{
	import flash.geom.Point;

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
		public var position:Point = new Point();
		public var nextPosition:Point = new Point();
	}
}