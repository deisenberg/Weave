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
	
	import mx.utils.ObjectUtil;
	
	import weave.Weave;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IFilteredKeySet;
	import weave.api.data.IQualifiedKey;
	import weave.api.getCallbackCollection;
	import weave.api.primitives.IBounds2D;
	import weave.core.LinkableHashMap;
	import weave.core.LinkableNumber;
	import weave.data.AttributeColumns.AlwaysDefinedColumn;
	import weave.data.AttributeColumns.ColorColumn;
	import weave.data.AttributeColumns.DynamicColumn;
	import weave.data.CSVParser;
	import weave.primitives.Bounds2D;
	import weave.primitives.GraphEdge;
	import weave.primitives.GraphNode;
	import weave.primitives.LinkableBounds2D;
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
		private var _idToNode:Array = [];
		private var _idToConnectedNodes:Array = [];
		
		public const lineStyle:DynamicLineStyle = newNonSpatialProperty(DynamicLineStyle);
		
		public const fillStyle:DynamicFillStyle = newNonSpatialProperty(DynamicFillStyle)
		
		public const colorColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn());
		public const nodesColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public const edgeSourceColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public const edgeTargetColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public const positionBounds:LinkableBounds2D = registerSpatialProperty(new LinkableBounds2D());
		
		public const radius:LinkableNumber = registerSpatialProperty(new LinkableNumber(5)); // radius of the circles
		public const minimumEnergy:LinkableNumber = registerSpatialProperty(new LinkableNumber(0.1)); // if less than this, close enough
		public const attractionConstant:LinkableNumber = registerSpatialProperty(new LinkableNumber(0.1)); // made up spring constant in hooke's law
		public const repulsionConstant:LinkableNumber = registerSpatialProperty(new LinkableNumber(1)); // coulumb's law constant
		public const dampingConstant:LinkableNumber = registerSpatialProperty(new LinkableNumber(0.75)); // the amount of damping on the forces
		public const maxIterations:LinkableNumber = registerSpatialProperty(new LinkableNumber(1000)); // max iterations
		public const nodeSeparation:LinkableNumber = registerSpatialProperty(new LinkableNumber(15)); // the minimum separation (this is used for the equilibrium point
		
		private const netForce:Point = new Point(); // the force vector
		private const tempPoint:Point = new Point(); // temp point used for computing force 
		private var outputBounds:IBounds2D = new Bounds2D();
		
		public function recomputePositions():void 
		{ 
			initializeWrappers(); 
			computeLocations(); 
		}
		
		private function handleColumnsChange():void
		{
			_idToNode.length = 0;
			_idToConnectedNodes.length = 0;
			_edges.length = 0;
			
			// set the keys
			setKeySource(nodesColumn);
			
			// if we don't have the required keys, do nothing
			if (nodesColumn.keys.length == 0 || edgeSourceColumn.keys.length == 0 || edgeTargetColumn.keys.length == 0)
				return;
			if (edgeSourceColumn.keys.length != edgeTargetColumn.keys.length)
				return;

			// setup the lookups and objects
			setupData();
									
			// initialize everything to positions and velocities
			initializeWrappers();
			
			// compute their locations
			computeLocations();
		}

		private function hookeAttraction(a:GraphNode, b:GraphNode, output:Point = null):Point
		{
			if (!output) 
				output = new Point();
			
			var dx:Number = b.position.x - a.position.x;
			var dy:Number = b.position.y - a.position.y;
			var dx2:Number = dx * dx;
			var dy2:Number = dy * dy;			
			var resultantVectorMagnitude:Number = Math.sqrt(dx2 + dy2);
			
			var forceMagnitude:Number = attractionConstant.value * Math.max(resultantVectorMagnitude - nodeSeparation.value, 0); // F = -kx 
			var angle:Number = Math.atan2(dy, dx); // y parameter first--go Adobe

			if (isNaN(angle))
				trace('nan angle attraction');
			
			output.x = forceMagnitude * Math.cos(angle);
			output.y = forceMagnitude * Math.sin(angle);
			
			//trace(dx, dy, output);
			//trace( a.node.id,', ', b.node.id, ', ', output.x, ', ', output.y);
			return output; 
		}
		
		private function coulumbRepulsion(a:GraphNode, b:GraphNode, output:Point = null):Point
		{
			if (!output) 
				output = new Point();
			
			var dx:Number = a.position.x - b.position.x;
			var dy:Number = a.position.y - b.position.y;
			var dx2:Number = dx * dx;
			var dy2:Number = dy * dy;			
			var resultantVectorMagnitude:Number = dx2 + dy2;
			
			var forceMagnitude:Number = repulsionConstant.value / resultantVectorMagnitude; 
			var angle:Number = Math.atan2(dy, dx); // y is first parameter--read Adobe's documentation online
			
			if (isNaN(angle))
				trace('nan angle repulsion');
			
			output.x = forceMagnitude * Math.cos(angle);
			output.y = forceMagnitude * Math.sin(angle);
			
			//trace( a.node.id,', ', b.node.id, ', ', output.x, ', ', output.y);
			return output;
		}
		private function computeLocations():IBounds2D
		{
			outputBounds.reset();
			var currentNode:GraphNode;
			
			var kineticEnergy:Number = 0;
			var damping:Number = 0.25;
			var timeStep:Number = .5;
			
			var tempDistance:Number;
			var iterations:int = 0;
			while (true)
			{
				for each (currentNode in _idToNode)
				{
					netForce.x = 0;
					netForce.y = 0;
					
					// calculate repulsion for every node except
					for each (var otherNode:GraphNode in _idToNode)
					{
						if (currentNode == otherNode) 
							continue;
						
						var tempRepulsion:Point = coulumbRepulsion(currentNode, otherNode, tempPoint);
						netForce.x += tempRepulsion.x;
						netForce.y += tempRepulsion.y;
					}
					
					// calculate edge attraction in connected nodes
					var connectedNodes:Array = _idToConnectedNodes[currentNode.id];
					for each (var connectedNode:GraphNode in connectedNodes)
					{
						var tempAttraction:Point = hookeAttraction(currentNode, connectedNode, tempPoint);
						netForce.x += tempAttraction.x;
						netForce.y += tempAttraction.y;
					}
					//trace(currentNode.id, '\t', netForce.x, netForce.y);
					
					// calculate velocity
					currentNode.velocity.x = (currentNode.velocity.x + netForce.x) * damping;
					currentNode.velocity.y = (currentNode.velocity.y + netForce.y) * damping;
					
					// determine the next position (don't modify the current position because we need it for calculating KE
					currentNode.nextPosition.x = currentNode.position.x + currentNode.velocity.x;
					currentNode.nextPosition.y = currentNode.position.y + currentNode.velocity.y;
				}

				// calculate the KE and update positions
				kineticEnergy = 0;
				for each (var gnw:GraphNode in _idToNode)
				{
					var pos:Point = gnw.position;
					var nextPos:Point = gnw.nextPosition;
					var dx:Number = pos.x - nextPos.x;
					var dy:Number = pos.y - nextPos.y;
					kineticEnergy += Math.sqrt(dx * dx + dy * dy);

					gnw.position.x = nextPos.x;
					gnw.position.y = nextPos.y;
				}
				
				//trace(kineticEnergy);
				if (kineticEnergy < minimumEnergy.value)
					break;
				
				if (++iterations > maxIterations.value)
					break;
			} 
			
			for each (currentNode in _idToNode)
			{
				outputBounds.includePoint(currentNode.position);				
			}
			
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
			positionBounds.copyFrom(outputBounds);
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
			var x:Number;
			var y:Number;
			
			//lineStyle.beginLineStyle(recordKey, graphics);				
			//fillStyle.beginFillStyle(recordKey, graphics);
			graphics.beginFill(0xFF0000, 1);
			graphics.lineStyle(1, 0x000000, .5);
						
			for each (var edge:GraphEdge in _edges)
			{
				var source:GraphNode = _idToNode[edge.source.id];
				var target:GraphNode = _idToNode[edge.target.id];
				
				var sourcePoint:Point = source.position;
				projectPoint(sourcePoint.x, sourcePoint.y);
				graphics.moveTo(screenPoint.x, screenPoint.y);
				var targetPoint:Point = target.position;
				projectPoint(targetPoint.x, targetPoint.y);
				graphics.lineTo(screenPoint.x, screenPoint .y);
			}
			
			// loop through each node, drawing what it's connected to
			for each (var nodeWrapper:GraphNode in _idToNode)
			{
				x = nodeWrapper.position.x;
				y = nodeWrapper.position.y;
				projectPoint(x, y);
									
				graphics.drawCircle(screenPoint.x, screenPoint.y, radius.value);
			}
			graphics.endFill();
			destination.draw(tempShape, null, null, null, null, false);
		}

		private const coordinate:Point = new Point();//reusable object
		private const _currentDataBounds:IBounds2D = new Bounds2D(); // reusable temporary object
		private const _currentScreenBounds:IBounds2D = new Bounds2D(); // reusable temporary object
		private const screenPoint:Point = new Point(); // reusable object, output of projectPoints()
		
		public function get alphaColumn():AlwaysDefinedColumn { return (fillStyle.internalObject as SolidFillStyle).alpha; }
		
		
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
			var gnw:GraphNode = _idToNode[id];
			var keyPoint:Point;
			if (gnw)
			{
				keyPoint = gnw.position;
				bounds.includePoint( keyPoint );
			}
			return [ bounds ];
		}

		/**
		 * This function returns a Bounds2D object set to the data bounds associated with the background.
		 * @param outputDataBounds A Bounds2D object to store the result in.
		 */
		override public function getBackgroundDataBounds():IBounds2D
		{
			return outputBounds.cloneBounds();
		}

		/**
		 * This function will setup the nodes and edges.
		 */
		private function setupData():void
		{
			var i:int;
			
			// setup the nodes map
			{ // force garbage collection
				var nodesKeys:Array = nodesColumn.keys;
				for (i = 0; i < nodesKeys.length; ++i)
				{
					var newNode:GraphNode = new GraphNode();
					newNode.id = nodesColumn.getValueFromKey(nodesKeys[i], Number) as Number;
					newNode.position.x = Math.random();
					newNode.position.y = Math.random();
					_idToNode[newNode.id] = newNode;
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
					var source:GraphNode = _idToNode[idSource];
					var target:GraphNode = _idToNode[idTarget];
					
					if (!source)
					{
						trace('no source node with id: ', idSource, ' exists');
						continue;
					}
					if (!target)
					{
						trace('no target node with id: ', idTarget, ' exists');
						continue;
					}
						
					newEdge.id = i;
					newEdge.source = source;
					newEdge.target = target;
					_edges.push(newEdge);
					
					var connectedNodes:Array = _idToConnectedNodes[source.id] || [];
					connectedNodes.push(target);
					_idToConnectedNodes[source.id] = connectedNodes;
					
					connectedNodes = _idToConnectedNodes[target.id] || [];
					connectedNodes.push(source);
					_idToConnectedNodes[target.id] = connectedNodes;
				}
			}
		}

		/**
		 * Set all of the positions to random values and zero the velocities.
		 */
		private function initializeWrappers():void
		{
			var i:int = 0;
			for each (var node:GraphNode in _idToNode)
			{
				node.position.x = Math.random();
				node.position.y = Math.random();
				node.velocity.x = 0;
				node.velocity.y = 0;
			}
		}
		
		/**
		 * This function projects data coordinates to screen coordinates and stores the result in screenPoint.
		 */
		private function projectPoint(x:Number, y:Number): void
		{
			screenPoint.x = x;     
			screenPoint.y = y;
			_currentDataBounds.projectPointTo(screenPoint, _currentScreenBounds);
		}
	}
}