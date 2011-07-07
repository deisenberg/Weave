package weave.primitives
{
	import flash.geom.Point;
	
	import weave.api.data.IQualifiedKey;
	import weave.api.primitives.IBounds2D;

	public class GraphNode
	{
		public function GraphNode()
		{
		}
		
		public var key:IQualifiedKey; // needed for fast lookups or something
		public var id:int;
		public var value:Object;
		public var label:String;
		
		public var isDrawn:Boolean = false;
		public var velocity:Point = new Point();
		public var position:Point = new Point();
		public var bounds:IBounds2D = new Bounds2D();
		
		public var nextPosition:Point = new Point();
		private const _connectedNodes:Vector.<GraphNode> = new Vector.<GraphNode>();
		
		public function addConnection(node:GraphNode):void
		{
			if (_connectedNodes.indexOf(node, 0) < 0)
				_connectedNodes.push(node);
		}
		public function removeConnection(node:GraphNode):void
		{
			var idx:int = _connectedNodes.indexOf(node, 0);
			if (idx < 0)
				return;
			_connectedNodes.splice(idx, 1);
		}
		public function get connections():Vector.<GraphNode>
		{
			return _connectedNodes;
		}
			
	}
}