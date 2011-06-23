/*
    Weave (Web-based Analysis and Visualization Environment)
    Copyright (C) 2008-2011 University of Massachusetts Lowell

    This file is a part of Weave.

    Weave is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License, Version 3,
    as published by the Free Software Foundation.

    Weave is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Weave.  If not, see <http://www.gnu.org/licenses/>.
*/

package weave.visualization.plotters
{
	import flash.display.BitmapData;
	import flash.display.Graphics;
	import flash.display.Shape;
	import flash.display.TriangleCulling;
	import flash.geom.Point;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	
	import weave.Weave;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IFilteredKeySet;
	import weave.api.data.IQualifiedKey;
	import weave.api.getCallbackCollection;
	import weave.api.primitives.IBounds2D;
	import weave.core.LinkableHashMap;
	import weave.data.AttributeColumns.AlwaysDefinedColumn;
	import weave.data.AttributeColumns.ColorColumn;
	import weave.data.AttributeColumns.DynamicColumn;
	import weave.data.CSVParser;
	import weave.primitives.Bounds2D;
	import weave.primitives.GraphEdge;
	import weave.primitives.GraphNode;
	import weave.utils.BitmapText;
	import weave.utils.ColumnUtils;
	import weave.utils.ComputationalGeometryUtils;
	import weave.visualization.plotters.styles.DynamicFillStyle;
	import weave.visualization.plotters.styles.DynamicLineStyle;
	import weave.visualization.plotters.styles.SolidFillStyle;
	import weave.visualization.plotters.styles.SolidLineStyle;
	
	/**
	 * GraphPlotter
	 * 
	 * @author kmonico
	 */	
	public class GraphPlotter extends AbstractPlotter
	{
		public function GraphPlotter()
		{
			// initialize default line & fill styles
			lineStyle.requestLocalObject(SolidLineStyle, false);
			var fill:SolidFillStyle = fillStyle.requestLocalObject(SolidFillStyle, false);
			fill.color.internalDynamicColumn.requestGlobalObject(Weave.DEFAULT_COLOR_COLUMN, ColorColumn, false);
			
			registerNonSpatialProperties(Weave.properties.axisFontUnderline,Weave.properties.axisFontSize,Weave.properties.axisFontColor);

			
		}

		private var _edges:Array = [];
		private var _nodeIdToNodeWrapper:Array = [];
		private var _nodeWrapperToNodeWrappersArray:Array = [];
		//private var _nodeIdToDrawnBoolean:Array = [];
		//private var _nodeIdToPoint:Array = [];
		//private var _nodeIdToVelocity:Array = [];
		
		public const lineStyle:DynamicLineStyle = newNonSpatialProperty(DynamicLineStyle);
		
		public const fillStyle:DynamicFillStyle = newNonSpatialProperty(DynamicFillStyle)
		
		public const colorColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn());
		public var nodesColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public var edgeSourceColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public var edgeTargetColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
				
		public const radius:Number = 5; // radius of the circles
		private const minimumEnergy:Number = .1; // if less than this, close enough
		private const maxIterations:int = 1000; // max iterations for the outer loop
		private const attractionConstant:Number = 0.1; // made up spring constant in hooke's law
		private const repulsionConstant:Number = 1000; // coulumb's law constant
		private const dampingConstant:Number = 0.5; // the amount of damping on the forces
		private const netForce:Point = new Point(); // the force vector
		private const tempPoint:Point = new Point(); // temp point used for computing force 
		private const outputBounds:IBounds2D = new Bounds2D();
		
		public function recomputePositions():void { initializeWrappers(); computeLocations(); getCallbackCollection(this).triggerCallbacks(); }
		
		private function handleColumnsChange():void
		{
			// set the keys
			setKeySource(nodesColumn);
			
			// setup the lookups and objects
			setupData();
						
			// initialize everything to positions and velocities
			initializeWrappers();
			
			// compute their locations
			computeLocations();
			
		}
		private function setupData():void
		{
			if (nodesColumn.keys.length == 0 || edgeSourceColumn.keys.length == 0 || edgeTargetColumn.keys.length == 0)
				return;
			
			_nodeIdToNodeWrapper.length = 0;
			_nodeWrapperToNodeWrappersArray.length = 0;
			
			var i:int;
			
			// setup the nodes map
			{ // force garbage collection
				var nodesKeys:Array = nodesColumn.keys;
				for (i = 0; i < nodesKeys.length; ++i)
				{
					var newNodeWrapper:GraphNodeWrapper = new GraphNodeWrapper(new GraphNode());
					newNodeWrapper.node.id = nodesColumn.getValueFromKey(nodesKeys[i], Number) as Number;
					newNodeWrapper.position.x = Math.random();
					newNodeWrapper.position.y = Math.random();
					_nodeIdToNodeWrapper[newNodeWrapper.node.id] = newNodeWrapper;
				}
				nodesKeys = null;
			}
			
			// setup the edges array
			{ // force garbage collection
				var edgesKeys:Array = edgeSourceColumn.keys;
				for (i = 0; i < edgesKeys.length; ++i)
				{
					var edgeKey:IQualifiedKey = edgesKeys[i] as IQualifiedKey;
					var idSource:int = edgeSourceColumn.getValueFromKey(edgeKey, int) as int;
					var idTarget:int = edgeTargetColumn.getValueFromKey(edgeKey, int) as int;
					var newEdge:GraphEdge = new GraphEdge();
					var sourceWrapper:GraphNodeWrapper = _nodeIdToNodeWrapper[idSource];
					var targetWrapper:GraphNodeWrapper = _nodeIdToNodeWrapper[idTarget];
					
					if (!sourceWrapper)
					{
						trace('no source node with id: ', idSource, ' exists');
						continue;
					}
					if (!targetWrapper)
					{
						trace('no target node with id: ', idTarget, ' exists');
						continue;
					}
						
					newEdge.id = i;
					newEdge.source = sourceWrapper.node;
					newEdge.target = targetWrapper.node;
					_edges.push(newEdge);
					
					var currentConnectedNodeWrappers:Array = _nodeWrapperToNodeWrappersArray[sourceWrapper] || [];
					currentConnectedNodeWrappers.push(targetWrapper);
					_nodeWrapperToNodeWrappersArray[sourceWrapper] = currentConnectedNodeWrappers; 
				}
			}
		}
		
		private function initializeWrappers():void
		{
			for each (var wrapper:GraphNodeWrapper in _nodeIdToNodeWrapper)
			{
				wrapper.position.x = Math.random();
				wrapper.position.y = Math.random();
				wrapper.velocity.x = 0;
				wrapper.velocity.y = 0;
			}
		}
		private function hookeAttraction(a:GraphNodeWrapper, b:GraphNodeWrapper, output:Point = null):Point
		{
			if (!output) 
				output = new Point();
			
			var dx:Number = b.position.x - a.position.x;
			var dy:Number = b.position.y - a.position.y;

			if (dx != 0 && dy != 0)
			{
				output.x = attractionConstant * dx;
				output.y = attractionConstant * dy;
			}
			else
			{
				output.x = 0;
				output.y = 0;
			}
			
			return output; 
		}
		private function coulumbRepulsion(a:GraphNodeWrapper, b:GraphNodeWrapper, output:Point = null):Point
		{
			if (!output) 
				output = new Point();
			
			var dx:Number = a.position.x - b.position.x;
			var dx2:Number = dx * dx;
			var dy:Number = a.position.y - b.position.y;
			var dy2:Number = dy * dy;			
			var resultantVectorMagnitude:Number = dx2 + dy2;

			if (resultantVectorMagnitude != 0)
			{
				resultantVectorMagnitude = Math.sqrt(resultantVectorMagnitude);
				var forceMagnitude:Number = repulsionConstant / resultantVectorMagnitude; 
				var angle:Number = Math.atan2(dy, dx); // y is first parameter--read Adobe's documentation online
				output.x = forceMagnitude * Math.cos(angle);
				output.y = forceMagnitude * Math.sin(angle);
			}
			else
			{
				output.x = repulsionConstant;
				output.y = repulsionConstant;
			}
			
			return output;
		}
		private function computeLocations():IBounds2D
		{
			outputBounds.reset();
			var nodeWrapper:GraphNodeWrapper;
			
			var kineticEnergy:Number = 0;
			var lastKineticEnergy:Number;
			var damping:Number = 0.25;
			var timeStep:Number = .5;
			
			var tempDistance:Number;
			var iterations:int = 0;
			while (true)
			{
				kineticEnergy = 0;
				for each (nodeWrapper in _nodeIdToNodeWrapper)
				{
					var node:GraphNode = nodeWrapper.node;
					
					// reset netForce
					netForce.x = 0;
					netForce.y = 0;
					
					// calculate repulsion for every node except
					for each (var otherNodeWrapper:GraphNodeWrapper in _nodeIdToNodeWrapper)
					{
						if (nodeWrapper == otherNodeWrapper) 
							continue;
						
						var tempRepulsion:Point = coulumbRepulsion(nodeWrapper, otherNodeWrapper, tempPoint);
						netForce.x += tempRepulsion.x;
						netForce.y += tempRepulsion.y;
					}
					
					// calculate edge attraction
					var connectedNodeWrappers:Array = _nodeWrapperToNodeWrappersArray[nodeWrapper];
					for each (var connectedNode:GraphNodeWrapper in connectedNodeWrappers)
					{
						var tempAttraction:Point = hookeAttraction(nodeWrapper, connectedNode, tempPoint);
						netForce.x += tempAttraction.x;
						netForce.y += tempAttraction.y;
					}
					
					// calculate velocity
					nodeWrapper.velocity.x = (nodeWrapper.velocity.x + netForce.x) * damping;
					nodeWrapper.velocity.y = (nodeWrapper.velocity.y + netForce.y) * damping;
					
					// determine the next position (don't modify the current position because we need it for calculating KE
					nodeWrapper.nextPosition.x = nodeWrapper.position.x + nodeWrapper.velocity.x;
					nodeWrapper.nextPosition.y = nodeWrapper.position.y + nodeWrapper.velocity.y;
				}

				// calculate the KE and update positions
				for each (var gnw:GraphNodeWrapper in _nodeIdToNodeWrapper)
				{
					var pos:Point = gnw.position;
					var nextPos:Point = gnw.nextPosition;
					var dx:Number = pos.x - nextPos.x;
					var dy:Number = pos.y - nextPos.y;
					kineticEnergy += Math.sqrt(dx * dx + dy * dy);

					gnw.position.x = nextPos.x;
					gnw.position.y = nextPos.y;
				}
				
				++iterations;
				
				if (kineticEnergy < minimumEnergy)
					break;
				
				if (iterations > maxIterations)
					break;
			} 
			
			for each (nodeWrapper in _nodeIdToNodeWrapper)
			{
				outputBounds.includePoint(nodeWrapper.position);				
			}
			
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
			return outputBounds;
		}
		override public function drawPlot(recordKeys:Array, dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			if (recordKeys.length == 0)
				return;

			_currentDataBounds.copyFrom(dataBounds);
			_currentScreenBounds.copyFrom(screenBounds);

			var tempShape:Shape = new Shape();
			var graphics:Graphics = tempShape.graphics;
			graphics.clear();
			var i:int;
			var count:int = 0;
			var xMin:Number = _currentDataBounds.getXMin();
			var xMax:Number = _currentDataBounds.getXMax();
			var yMin:Number = _currentDataBounds.getYMin();
			var yMax:Number = _currentDataBounds.getYMax();
			var width:Number = _currentDataBounds.getWidth();
			var height:Number = _currentDataBounds.getHeight();
			
			graphics.beginFill(0xFF0000, 1);
			graphics.lineStyle(2, 0x0000FF, 1);

			// loop through each node, drawing what it's connected to
			for each (var nodeWrapper:GraphNodeWrapper in _nodeIdToNodeWrapper)
			{
				var x:Number = nodeWrapper.position.x;
				var y:Number = nodeWrapper.position.y;
				projectPoint(x, y);
									
				graphics.drawCircle(screenPoint.x, screenPoint.y, radius);
			}
			
			graphics.endFill();
			destination.draw(tempShape, null, null, null, null, false);
		}

		private const coordinate:Point = new Point();//reusable object
		
		private const _currentDataBounds:IBounds2D = new Bounds2D(); // reusable temporary object
		private const _currentScreenBounds:IBounds2D = new Bounds2D(); // reusable temporary object
		
		public function get alphaColumn():AlwaysDefinedColumn { return (fillStyle.internalObject as SolidFillStyle).alpha; }
		
		/**
		 * This function projects data coordinates to screen coordinates and stores the result in screenPoint.
		 */
		private function projectPoint(x:Number, y:Number): void
		{
			screenPoint.x = x;     
			screenPoint.y = y;
			_currentDataBounds.projectPointTo(screenPoint, _currentScreenBounds);
		}

		private const screenPoint:Point = new Point(); // reusable object, output of projectPoints()
		
		/**
		 * The data bounds for a glyph has width and height equal to zero.
		 * This function returns a Bounds2D object set to the data bounds associated with the given record key.
		 * @param key The key of a data record.
		 * @param outputDataBounds A Bounds2D object to store the result in.
		 */
		override public function getDataBoundsFromRecordKey(recordKey:IQualifiedKey):Array
		{
			var bounds:IBounds2D = getReusableBounds();
			var id:int = nodesColumn.getValueFromKey(recordKey, int) as int;
			var gnw:GraphNodeWrapper = _nodeIdToNodeWrapper[id] as GraphNodeWrapper;
			var keyPoint:Point;
			if (gnw)
			{
				keyPoint = gnw.position;
				bounds.includePoint( keyPoint );
			}
			trace(bounds);
			return [ bounds ];
		}

		/**
		 * This function returns a Bounds2D object set to the data bounds associated with the background.
		 * @param outputDataBounds A Bounds2D object to store the result in.
		 */
		override public function getBackgroundDataBounds():IBounds2D
		{
			return outputBounds.cloneBounds();
			//getReusableBounds(-1, -1, 1, 1);
		}

/*		private function parseData():void
		{
			var i:int;
			var byteArray:ByteArray = new _testDataClass();
			var dataString:String = byteArray.readUTFBytes(byteArray.length);
			_testDataXML = XML(dataString);
			
			var xmlEdges:XMLList = (_testDataXML.descendants("edges")[0] as XML).children();
			var xmlNodes:XMLList = (_testDataXML.descendants("nodes")[0] as XML).children();
			
			// first build the nodes
			for (i = 0; i < xmlNodes.length(); ++i)
			{
				var xmlNode:XML = xmlNodes[i];
				var newNodeWrapper:GraphNodeWrapper = new GraphNodeWrapper(new GraphNode(), new Point(), new Point()); 
				newNodeWrapper.node.label = xmlNode.@label;
				newNodeWrapper.node.id = xmlNode.@id;
				_nodeIdToNodeWrapper[newNodeWrapper.node.id] = newNodeWrapper;
			}
			
			// next build the edges
			for (i = 0; i < xmlEdges.length(); ++i)
			{
				var xmlEdge:XML = xmlEdges[i];
				var newEdge:GraphEdge = new GraphEdge();
				newEdge.source = _nodeIdToNodeWrapper[xmlEdge.@source].node;
				newEdge.target = _nodeIdToNodeWrapper[xmlEdge.@target].node;
				newEdge.id = xmlEdge.@id;
				newEdge.isDirected = xmlEdge.@type == "dir";
				_edges.push(newEdge);
			}		
			
			trace(_nodeIdToNodeWrapper.length);
			trace(_edges.length);
		}*/
	}
}
import flash.geom.Point;

import weave.primitives.GraphNode;


internal class GraphNodeWrapper
{
	public function GraphNodeWrapper(_node:GraphNode, _isDrawn:Boolean = false)
	{
		node = _node;
		isDrawn = _isDrawn;
	}
	
	public var node:GraphNode;
	public var isDrawn:Boolean = false;
	public var velocity:Point = new Point();
	public var position:Point = new Point();
	public var nextPosition:Point = new Point();
}