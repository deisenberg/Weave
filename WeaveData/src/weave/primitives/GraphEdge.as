package weave.primitives
{
	public class GraphEdge
	{
		public function GraphEdge()
		{
		}
		
		public var source:GraphNode;
		public var target:GraphNode;
		public var weight:Number;
		public var isDirected:Boolean = true;
		public var id:int;
	}
}