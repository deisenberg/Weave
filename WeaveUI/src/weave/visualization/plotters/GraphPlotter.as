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
	import flash.display.LineScaleMode;
	import flash.display.Shape;
	import flash.display.TriangleCulling;
	import flash.geom.Point;
	import flash.sampler.DeleteObjectSample;
	import flash.utils.ByteArray;
	import flash.utils.Dictionary;
	
	import mx.utils.ObjectUtil;
	
	import weave.Weave;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IFilteredKeySet;
	import weave.api.data.IQualifiedKey;
	import weave.api.getCallbackCollection;
	import weave.api.primitives.IBounds2D;
	import weave.core.ErrorManager;
	import weave.core.LinkableBoolean;
	import weave.core.LinkableHashMap;
	import weave.core.LinkableNumber;
	import weave.core.LinkableString;
	import weave.core.StageUtils;
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
	 * This is a plotter for a node edge chart, commonly referred to as a Graph.
	 * This plotter has different layout algorithms, each with the ability to stop,
	 * continue, and restart.
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
			
			init();
		}
	
		/**
		 * Initialize the algorithms array.
		 */
		public function init():void
		{
			algorithms[FORCE_DIRECTED] = forceDirected;
			algorithms[FADE] = fade;
			algorithms[INCREMENTAL] = incremental;
			algorithms[RADIAL] = radial;
			
			resetAllNodes();
		}
	
		/**
		 * Recompute the positions of the nodes in the graph and then draw the plot.
		 */
		public function recomputePositions():void 
		{ 
			try 
			{
				//resetAllNodes();
				_iterations = 0;
				_nextIncrement = 0;
				_algorithm(); 
			} 
			catch (e:Error)
			{
				ErrorManager.reportError(e);
			}
		}
		
		/**
		 * Continue the algorithm.
		 */
		public function continueComputation():void
		{
			try
			{
				_algorithm();
			}
			catch (e:Error)
			{
				ErrorManager.reportError(e);
			}
		}
				
		private function changeAlgorithm():void
		{
			var newAlgorithm:Function = algorithms[currentAlgorithm.value];
			if (newAlgorithm == null)
				return;
			
			_algorithm = newAlgorithm;
		}
		
		// the graph's specification
		private var _edges:Object = []; // list of edges
		private var _idToNode:Object = [];  // int -> GraphNode
		private var _idToConnectedNodes:Object = []; // int -> Array (of GraphNode objects)
		private const _allowedBounds:IBounds2D = new Bounds2D(-100, -100, 100, 100);
		
		// styles
		public const lineStyle:DynamicLineStyle = newNonSpatialProperty(DynamicLineStyle);
		public const fillStyle:DynamicFillStyle = newNonSpatialProperty(DynamicFillStyle);

		// the columns
		public var colorColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn());
		public var sizeColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn());
		public const nodesColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public const edgeSourceColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public const edgeTargetColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		
		// the algorithms
		[Bindable] public var algorithms:Array = [ FORCE_DIRECTED, FADE, INCREMENTAL, RADIAL]; // choices
		public const currentAlgorithm:LinkableString = registerNonSpatialProperty(new LinkableString('Force Directed'), changeAlgorithm); // the algorithm
		private var _algorithm:Function = null; // current algorithm function
		private static const FORCE_DIRECTED:String = "Force Directed";
		private static const FADE:String = "FADE";
		private static const INCREMENTAL:String = "Incremental";
		private static const RADIAL:String = "RADIAL";

		public const radius:LinkableNumber = registerSpatialProperty(new LinkableNumber(2)); // radius of the circles
		public const minimumEnergy:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.1)); // if less than this, close enough
		public const attractionConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.1)); // made up spring constant in hooke's law
		public const repulsionConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(1)); // coulumb's law constant
		public const dampingConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.75)); // the amount of damping on the forces
		public const maxIterations:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(1000), handleIterations); // max iterations
		public const drawIncrement:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(200)); // the number of iterations between drawPlot calls	
		public const nodeSeparation:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(15)); // the minimum separation (this is used for the equilibrium point
		public const shouldStop:LinkableBoolean = registerNonSpatialProperty(new LinkableBoolean(false)); // should the algorithm halt on the next iteration? 
		public const algorithmRunning:LinkableBoolean = registerNonSpatialProperty(new LinkableBoolean(false)); // is an algorithm running?
		
		private function handleIterations():void { }

		private function handleNodeSort(a:GraphNode, b:GraphNode):int
		{
			// we want higher degrees to come first in the array
			a.isDrawn = true;
			b.isDrawn = true;
			var aList:Array = _idToConnectedNodes[a.id];
			var bList:Array = _idToConnectedNodes[a.id];
			
			if (aList == null && bList == null)
				return 0;
			if (aList == null)
				return 1;
			if (bList == null)
				return -1;
			
			var aLength:int = aList.length;
			var bLength:int = bList.length;
			if (aLength > bLength)
				return -1;
			else if (bLength > aLength)
				return 1;
			
			return 0;
		}
		
		private var _idToRadius:Object;
		public const maxLevels:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(2)); 
		private function radial():void
		{
			outputBounds.reset();
			algorithmRunning.value = true;
			
			_idToRadius = [];
			
			// visited array
			var idToVisitedNodes:Array = [];
			
			// sorted nodes
			var nodes:Array = (_idToNode as Array).concat();
			nodes.sort(handleNodeSort);
			
			// get the root node and visit it
			var parentNode:GraphNode = nodes.shift();
			nodes.unshift(parentNode);
			idToVisitedNodes[parentNode.id] = true;
			parentNode.position.x = 0;
			parentNode.position.y = 0;

			var connectedNodesLength:Number = getNumUnvisitedConnectedNodes(parentNode, idToVisitedNodes); 
			var r:Number = connectedNodesLength * radius.value * 2;	 // seeding radius
			var positionRadius:Number = r; // the initial positioning radius of the children
			_idToRadius[parentNode.id] = r; // the radius of the drawn circle for the root node
			var angleSpacing:Number = 2 * Math.PI / connectedNodesLength; // the angular degree between points
			var angle:Number = 0; // current angle
			var level:int = 1; // current level 
			var previousLevel:int = 0; // previous level
			var queue:Array = [parentNode, level];
			while (queue.length > 0) //&& previousLevel <= maxLevels.value)
			{
				parentNode.isDrawn = false;
				// get this node and level
				parentNode = queue.shift();
				level = queue.shift();
								
				connectedNodesLength = getNumUnvisitedConnectedNodes(parentNode, idToVisitedNodes);
				if (connectedNodesLength == 0) 
					angleSpacing = 0;
				else
					angleSpacing = 2 * Math.PI / connectedNodesLength;
				angle = 2 * Math.PI * Math.random();

				// if we changed level, save the previous level radius 
				// to use for calculating the radius of all nodes in this level
				if (level > previousLevel)
				{
					positionRadius = r;
					r = Math.abs(r * Math.sin(angleSpacing / 2)); 
					previousLevel = level;
				}

				// for each of the unvisited, connected nodes
				for each (var target:GraphNode in _idToConnectedNodes[parentNode.id])
				{
					if (idToVisitedNodes[target.id] == null)
					{
						_idToRadius[target.id] = r; // save the radius size 
						
						queue.push(target, level + 1);	// push the node and its level
						idToVisitedNodes[target.id] = true; // mark as visited
						target.position.x = parentNode.position.x + positionRadius * Math.cos(angle); // compute its position from the currentNode
						target.position.y = parentNode.position.y + positionRadius * Math.sin(angle);

						outputBounds.includePoint(target.position); // include this point	
					}
					angle += angleSpacing; // increment the angle
				}				
			}
			
			// resize the bounds so it looks nice
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
			
			// rebuild spatial index
			_spatialCallbacks.triggerCallbacks();
			
			// trigger drawing callbacks
			getCallbackCollection(this).triggerCallbacks();
			
			algorithmRunning.value = false;
		}
		private function getNumUnvisitedConnectedNodes(sourceNode:GraphNode, visitedArray:Array):int
		{
			var connectedNodesLength:int = 0;
			var connectedNodes:Array = _idToConnectedNodes[sourceNode.id];
			
			for each (var target:GraphNode in connectedNodes)
			{
				if (visitedArray[target.id] == null)
					connectedNodesLength++;
			}
			return connectedNodesLength;
		}
		// FINISH THESE
		private function fade():IBounds2D
		{
			return outputBounds;
		}
		private function incremental():IBounds2D 
		{ 
			return outputBounds;
		}

		private var _iterations:int = 0;
		private var _nextIncrement:int = 0;
		
		override public function drawPlot(recordKeys:Array, dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			if (recordKeys.length == 0)
				return;
			
			_currentDataBounds.copyFrom(dataBounds);
			_currentScreenBounds.copyFrom(screenBounds);

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
			
			// loop through each node and draw it
			for each (var key:IQualifiedKey in recordKeys)
			{
				var id:int = nodesColumn.getValueFromKey(key, int);
				var connections:Array = _idToConnectedNodes[id];
				if (connections == null || connections.length == 0)
					continue;
				var node:GraphNode = _idToNode[id];
				if (node.isDrawn == true) 
					continue;
				
				x = node.position.x;
				y = node.position.y;
				projectPoint(x, y);
									
				lineStyle.beginLineStyle(key, graphics);				
				fillStyle.beginFillStyle(key, graphics);
				
				graphics.drawCircle(screenPoint.x, screenPoint.y, radius.value);
			}

			destination.draw(tempShape, null, null, null, null, false);
		}
		
		override public function drawBackground(dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			_currentDataBounds.copyFrom(dataBounds);
			_currentScreenBounds.copyFrom(screenBounds);

			if (_algorithm == radial)
			{
				drawRadialBackground(dataBounds, screenBounds, destination);
				return;
			}
			
			var graphics:Graphics = tempShape.graphics;
			graphics.clear();
			
			graphics.beginFill(0xFF0000, 1);
			graphics.lineStyle(1, 0x000000, .2);
						
			for each (var edge:GraphEdge in _edges)
			{
				var source:GraphNode = _idToNode[edge.source.id];
				var target:GraphNode = _idToNode[edge.target.id];
				if (source.isDrawn == true || source.isDrawn == true)
					continue;
				var sourcePoint:Point = source.position;
				projectPoint(sourcePoint.x, sourcePoint.y);
				graphics.moveTo(screenPoint.x, screenPoint.y);
				var targetPoint:Point = target.position;
				projectPoint(targetPoint.x, targetPoint.y);
				graphics.lineTo(screenPoint.x, screenPoint .y);
			}
			
			graphics.endFill();
			destination.draw(tempShape, null, null, null, null, false);
		}

		private function drawRadialBackground(dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			var graphics:Graphics = tempShape.graphics;
			graphics.clear();
			
			graphics.lineStyle(1, 0x000000, 0.5);

			for each (var edge:GraphEdge in _edges)
			{
				var source:GraphNode = _idToNode[edge.source.id];
				var target:GraphNode = _idToNode[edge.target.id];
				if (source.isDrawn || target.isDrawn)
					continue;
				
				var sourcePoint:Point = source.position;
				projectPoint(sourcePoint.x, sourcePoint.y);
				graphics.moveTo(screenPoint.x, screenPoint.y);
				var targetPoint:Point = target.position;
				projectPoint(targetPoint.x, targetPoint.y);
				graphics.lineTo(screenPoint.x, screenPoint .y);
			}
			

			if (_idToRadius != null)
			{
				graphics.lineStyle(1, 0x111111, 0.2, false, LineScaleMode.NONE);
				for each (var node:GraphNode in _idToNode)
				{
					if (node.isDrawn) continue;
					
					var xCenterData:Number = node.position.x;
					var yCenterData:Number = node.position.y;
					projectPoint(xCenterData, yCenterData);
					var xCenterScreen:Number = screenPoint.x;
					var yCenterScreen:Number = screenPoint.y;
					
					var x1:Number = xCenterData + _idToRadius[node.id];
					var y1:Number = yCenterData;
					projectPoint(x1, y1);
					var x2:Number = screenPoint.x;
					var y2:Number = screenPoint.y;
					var r:Number = ComputationalGeometryUtils.getDistanceFromPoint(xCenterScreen, yCenterScreen, x2, y2);
					if (isNaN(xCenterData) || isNaN(yCenterData))
						trace(node.id);
					if (isNaN(xCenterScreen) || isNaN(yCenterScreen))
						trace(node.id);
					if (r < 0)
						trace(node.id);
					graphics.drawCircle(xCenterScreen, yCenterScreen, r);
				}
			}
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
			var node:GraphNode = _idToNode[id];
			var keyPoint:Point;
			if (node)
			{
				keyPoint = node.position;
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
			return _allowedBounds.cloneBounds();
			//return outputBounds.cloneBounds();
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
						//trace('no source node with id: ', idSource, ' exists');
						continue;
					}
					if (!target)
					{
						//trace('no target node with id: ', idTarget, ' exists');
						continue;
					}
					if (source == target)
					{
						//trace('cannot have nodes connected to themselves');
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
		private function resetAllNodes():void
		{
			var i:int = 0;
			var length:int = 0;
			
			for each (var obj:* in _idToNode) { ++length; }
			
			var spacing:Number = 2 * Math.PI / (length + 1);
			var angle:Number = 0;
			for each (var node:GraphNode in _idToNode)
			{
				if (node == null)
				{
					trace('empty element in _idToNode');
					continue;
				}
				var x:Number = Math.cos(angle);
				var y:Number = Math.sin(angle);
				node.position.x = x; 
				node.position.y = y;
				angle += spacing;
				outputBounds.includePoint(node.position);
				
				node.velocity.x = 0;
				node.velocity.y = 0;
			}
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
			
			// verify source and target column have same keytype
			var sourceKey:IQualifiedKey = edgeSourceColumn.keys[0];
			var targetKey:IQualifiedKey = edgeTargetColumn.keys[0];
			if (sourceKey.keyType != targetKey.keyType)
				return;
			
			// setup the lookups and objects
			setupData();

			resetAllNodes();
			//recomputePositions();
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

		/**
		 * Calculate the hooke attraction on node a from spring b.
		 */
		private function hookeAttraction(a:GraphNode, b:GraphNode, output:Point = null):Point
		{
			if (!output) 
				output = new Point();
			
			var dx:Number = b.position.x - a.position.x;
			var dy:Number = b.position.y - a.position.y;
			var dx2:Number = dx * dx;
			var dy2:Number = dy * dy;			
			var distance:Number = Math.sqrt(dx2 + dy2);
			var forceMagnitude:Number = attractionConstant.value * (distance - nodeSeparation.value); 
			
			var forceX:Number = forceMagnitude * dx / distance;
			var forceY:Number = forceMagnitude * dy / distance;
			if (isNaN(forceX))
				forceX = 0;
			if (isNaN(forceY))
				forceY = 0;
			output.x = forceX;
			output.y = forceY;
			return output; 
		}
		/**
		 * Calculate the repulsion force on node a due to node b.
		 */
		private function coulumbRepulsion(a:GraphNode, b:GraphNode, output:Point = null):Point
		{
			if (!output) 
				output = new Point();
			
			var dx:Number = a.position.x - b.position.x;
			var dy:Number = a.position.y - b.position.y;
			var dx2:Number = dx * dx;
			var dy2:Number = dy * dy;			
			var resultantVectorMagnitude:Number = dx2 + dy2;
			if (resultantVectorMagnitude < 1)
				resultantVectorMagnitude = 1;
			var distance:Number = Math.sqrt(resultantVectorMagnitude);
  			var forceMagnitude:Number = repulsionConstant.value / resultantVectorMagnitude; 
			
			var forceX:Number = forceMagnitude * dx / distance;
			var forceY:Number = forceMagnitude * dy / distance;
			if (isNaN(forceX))
				forceX = 0;
			if (isNaN(forceY))
				forceY = 0;
			output.x = forceX;
			output.y = forceY;
			return output;
		}
		/**
		 * Update the positions of the nodes using a force directed layout.
		 */
		private function forceDirected():void
		{
			// if we should stop iterating
			if (shouldStop.value == true)
			{
				shouldStop.value = false;
				algorithmRunning.value = false;
				_spatialCallbacks.triggerCallbacks();
				return;
			}

			outputBounds.reset();
			algorithmRunning.value = true;
			var currentNode:GraphNode;
			var reachedEquilibrium:Boolean = false;
			var kineticEnergy:Number = 0;
			
			_nextIncrement += drawIncrement.value;
			var iterationsDelayed:Boolean = false;
			for (; _iterations < maxIterations.value; ++_iterations)
			{
				// if this function has run for more than 100ms, call later to finish
				if (StageUtils.shouldCallLater)
				{
					getCallbackCollection(this).triggerCallbacks();
					StageUtils.callLater(this, forceDirected, null, true);
					return;
				}
				
				for each (currentNode in _idToNode)
				{
					netForce.x = 0;
					netForce.y = 0;
					
					// calculate edge attraction in connected nodes
					var connectedNodes:Array = _idToConnectedNodes[currentNode.id];
					for each (var connectedNode:GraphNode in connectedNodes)
					{
						var tempAttraction:Point = hookeAttraction(currentNode, connectedNode, tempPoint);
						if (isNaN(tempPoint.x) || isNaN(tempPoint.y))
							trace('NaN Hooke');
						netForce.x += tempAttraction.x;
						netForce.y += tempAttraction.y;
					}
					if (connectedNodes == null || connectedNodes.length == 0)
						continue;
					
					// calculate repulsion with every node except itself
					for each (var otherNode:GraphNode in _idToNode)
					{
						if (currentNode == otherNode) 
							continue;
						
						var tempRepulsion:Point = coulumbRepulsion(currentNode, otherNode, tempPoint);
						if (isNaN(tempPoint.x) || isNaN(tempPoint.y))
							trace('NaN Repulsion');
						netForce.x += tempRepulsion.x;
						netForce.y += tempRepulsion.y;
					}
					
					// TODO: handle unconnected nodes (don't count their forces, but push them away)
					
					// trace(currentNode.id, '\t', netForce.x, netForce.y);
					
					if (isNaN(netForce.x) || isNaN(netForce.y))
						trace('NaN netForce');
					// calculate velocity
					currentNode.velocity.x = (currentNode.velocity.x + netForce.x) * dampingConstant.value;
					currentNode.velocity.y = (currentNode.velocity.y + netForce.y) * dampingConstant.value;
					
					// determine the next position (don't modify the current position because we need it for calculating KE
					currentNode.nextPosition.x = currentNode.position.x + currentNode.velocity.x;
					currentNode.nextPosition.y = currentNode.position.y + currentNode.velocity.y;
					
					_allowedBounds.constrainPoint(currentNode.nextPosition);
				}

				// calculate the KE and update positions
				kineticEnergy = 0;
				for each (currentNode in _idToNode)
				{
					var p1:Point = currentNode.position;
					var p2:Point = currentNode.nextPosition;
					kineticEnergy += ComputationalGeometryUtils.getDistanceFromPoint(p1.x, p1.y, p2.x, p2.y);

					p1.x = p2.x;
					p1.y = p2.y;
				}
				
				//trace(kineticEnergy);

				// if we've gone over the number of drawing iterations
				if (_iterations >= _nextIncrement)
				{
					_nextIncrement += drawIncrement.value;
					break;
				}
				
				// if we found the minimum or equilibrium
				if (kineticEnergy < minimumEnergy.value)
				{
					reachedEquilibrium = true;
					break;
				}
			} 
			
			// update the new outputbounds
			setOutputBounds();
			
			// if we reached equilibrium, rebuild the spatial index
			if (reachedEquilibrium == true || _iterations >= maxIterations.value)
				_spatialCallbacks.triggerCallbacks();
			else // or call later to finish
				StageUtils.callLater(this, forceDirected, null, true);
			
			// trigger drawing callbacks
			getCallbackCollection(this).triggerCallbacks();
			
			algorithmRunning.value = false;
		}
		
		/**
		 * Sets the output bounds.
		 */
		private function setOutputBounds():void
		{
			outputBounds.reset();
			for each (var node:GraphNode in _idToNode)
			{
				outputBounds.includePoint(node.position);				
			}
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
		}
		
		// reusable objects
		private const netForce:Point = new Point(); // the force vector
		private const tempPoint:Point = new Point(); // temp point used for computing force 
		private var outputBounds:IBounds2D = new Bounds2D(); 
	}
}