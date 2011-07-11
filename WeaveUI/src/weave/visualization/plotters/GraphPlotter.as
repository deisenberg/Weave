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
	import weave.api.data.IKeySet;
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
	import weave.utils.DebugTimer;
	import weave.visualization.plotters.styles.DynamicFillStyle;
	import weave.visualization.plotters.styles.DynamicLineStyle;
	import weave.visualization.plotters.styles.SolidFillStyle;
	import weave.visualization.plotters.styles.SolidLineStyle;
	
	/**
	 * This is a plotter for a node edge chart, commonly referred to as a graph.
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
			(lineStyle.internalObject as SolidLineStyle).scaleMode.defaultValue.value = LineScaleMode.NONE;
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
			algorithms[GRIP] = grip;
			resetAllNodes();
		}
	
		/**
		 * Recompute the positions of the nodes in the graph and then draw the plot.
		 */
		public function recomputePositions():void 
		{ 
			try 
			{
				resetAllNodes();
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
		 * Offset the x and y positions of the nodes with the corresponding keys in keys. 
		 */		
		public function updateDraggedKeys(keys:Array, dx:Number, dy:Number, runSpatialCallbacks:Boolean = true):void
		{
			for each (var key:IQualifiedKey in keys)
			{
				var node:GraphNode = _keyToNode[key];
				if (!node)
					continue;
				node.position.x += dx;
				node.position.y += dy;
			}
			setOutputBounds();
			if (runSpatialCallbacks)
				_spatialCallbacks.triggerCallbacks();
			getCallbackCollection(this).triggerCallbacks();
		}

//		/**
//		 * Set the keys to be drawn in the draggable layer.
//		 */
//		public function setDraggableLayerKeys(keys:Array):void
//		{
//			_draggedKeys = keys.concat();
//			// for each key, add the immediate neighbor to _draggedKeys
//			for each (var key:IQualifiedKey in keys)
//			{
//				var node:GraphNode = _keyToNode[key];
//				var connectedNodes:Vector.<GraphNode> = node.connections;
//				for each (var neighbor:GraphNode in connectedNodes)
//				{
//					var neighborKey:IQualifiedKey = neighbor.key;
//					if (_draggedKeys.indexOf(neighborKey) < 0)
//						_draggedKeys.push(neighborKey);
//				}
//			}
//		}
		
		/**
		 * Continue the algorithm.
		 */
		public function continueComputation(keys:Object = null):void
		{
			try
			{
				_algorithm(keys);
			}
			catch (e:Error)
			{
				ErrorManager.reportError(e);
			}
		}
		
		/**
		 * Run the force directed algorithm on only the keys.
		 * @param keys An array of IQualifiedKey objects. If this is null, the algorithm will
		 * be applied to every key.
		 */
		public function runForceDirect(keys:Array = null):void
		{
			try
			{
				forceDirected(keys);
			}
			catch (e:Error)
			{
				ErrorManager.reportError(e);
			}
		}
		
		/**
		 * Verify the algorithm string is correct and use the corresponding function.
		 */
		private function changeAlgorithm():void
		{
			var newAlgorithm:Function = algorithms[currentAlgorithm.value];
			if (newAlgorithm == null)
				return;
			
			_algorithm = newAlgorithm;
		}
		
		// the graph's specification
		private var _edges:Array = []; // Array of GraphEdges
		private var _keyToNode:Dictionary; // IQualifiedKey -> GraphNode
		private var _numNodes:int = 0; // the number of nodes in _keyToNode
		private const _allowedBounds:IBounds2D = new Bounds2D(-100, -100, 100, 100);
		
		// styles
		public const lineStyle:DynamicLineStyle = newNonSpatialProperty(DynamicLineStyle);
		public const fillStyle:DynamicFillStyle = newNonSpatialProperty(DynamicFillStyle);

		// the columns
		public const colorColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn());
		public const sizeColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn());
		public const nodesColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public const edgeSourceColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		public const edgeTargetColumn:DynamicColumn = registerSpatialProperty(new DynamicColumn(), handleColumnsChange);
		
		// the algorithms
		[Bindable] public var algorithms:Array = [ FORCE_DIRECTED, FADE, GRIP ]; // choices
		public const currentAlgorithm:LinkableString = registerNonSpatialProperty(new LinkableString(FORCE_DIRECTED), changeAlgorithm); // the algorithm
		private var _algorithm:Function = null; // current algorithm function
		private static const FORCE_DIRECTED:String = "Force Directed";
		private static const FADE:String = "FADE";
		private static const GRIP:String = "Intelligent Placement";
		
		// properties
		public const radius:LinkableNumber = registerSpatialProperty(new LinkableNumber(2)); // radius of the circles
		public const minimumEnergy:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.1)); // if less than this, close enough
		public const attractionConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.1)); // made up spring constant in hooke's law
		public const repulsionConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(1)); // coulumb's law constant
		public const dampingConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.75)); // the amount of damping on the forces
		public const maxIterations:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(1000), handleIterations); // max iterations
		public const drawIncrement:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(200)); // the number of iterations between drawPlot calls	
		public const shouldStop:LinkableBoolean = registerNonSpatialProperty(new LinkableBoolean(false)); // should the algorithm halt on the next iteration? 
		public const algorithmRunning:LinkableBoolean = registerNonSpatialProperty(new LinkableBoolean(false)); // is an algorithm running?
		
		//private var _draggedKeys:Array = []; // the keys in the dragged layer
		
		private function handleIterations():void { }

		// FINISH THESE
		private function fade(keys:Array = null):void { }

		private function grip(keys:Array = null):void { }
		
		override public function drawPlot(recordKeys:Array, dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			if (recordKeys.length == 0)
				return;
			
			_currentDataBounds.copyFrom(dataBounds);
			_currentScreenBounds.copyFrom(screenBounds);

			var nodesGraphics:Graphics = tempShape.graphics;
			var edgesGraphics:Graphics = edgesShape.graphics;
			nodesGraphics.clear();
			edgesGraphics.clear();
			var i:int;
			var count:int = 0;
			var x:Number;
			var y:Number;
			var fullyDrawnNodes:Dictionary = new Dictionary();
			
			// loop through each node and draw it
			for each (var key:IQualifiedKey in recordKeys)
			{
				var node:GraphNode = _keyToNode[key];
				var connections:Vector.<GraphNode> = node.connections;
//				if (connections == null || connections.length == 0)
//					continue;
				
				// set the styles
				lineStyle.beginLineStyle(key, nodesGraphics);				
				fillStyle.beginFillStyle(key, nodesGraphics);
				lineStyle.beginLineStyle(key, edgesGraphics);				
				fillStyle.beginFillStyle(key, edgesGraphics);

				// first draw the node
				x = node.position.x;
				y = node.position.y;
				projectPoint(x, y);
				var xNode:Number = screenPoint.x;
				var yNode:Number = screenPoint.y;
				nodesGraphics.drawCircle(xNode, yNode, radius.value);
				
				for each (var connectedNode:GraphNode in connections)
				{
					if (fullyDrawnNodes[connectedNode] != undefined)
					{						
						edgesGraphics.moveTo(xNode, yNode);
						x = connectedNode.position.x;
						y = connectedNode.position.y;
						projectPoint(x, y);
						edgesGraphics.lineTo(screenPoint.x, screenPoint.y);
					}
				}
				fullyDrawnNodes[node] = true;
			}
			destination.draw(edgesShape, null, null, null, null, false);
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
			var node:GraphNode = _keyToNode[recordKey];
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
			//return _allowedBounds.cloneBounds();
			return outputBounds.cloneBounds();
		}

		/**
		 * This function will setup the nodes and edges.
		 */
		private function setupData():void
		{
			_keyToNode = new Dictionary();
			_edges.length = 0;

			var idToNodeKey:Dictionary = new Dictionary();
			var i:int;

			// setup the nodes map
			{ // force garbage collection
				var nodesKeys:Array = nodesColumn.keys;
				_numNodes = nodesKeys.length;
				for (i = 0; i < nodesKeys.length; ++i)
				{
					var key:IQualifiedKey = nodesKeys[i];
					var newNode:GraphNode = new GraphNode();
					newNode.id = nodesColumn.getValueFromKey(key, Number) as Number;
					newNode.key = key;
					_keyToNode[key] = newNode;
					idToNodeKey[newNode.id] = key;
				}
				nodesKeys = null;
			}
			
			// setup the edges array
			{ // force garbage collection
				var edgesKeys:Array = edgeSourceColumn.keys;
				for (i = 0; i < edgesKeys.length; ++i)
				{
					var edgeKey:IQualifiedKey = edgesKeys[i];
					var idSource:int = edgeSourceColumn.getValueFromKey(edgeKey, int) as int;
					var idTarget:int = edgeTargetColumn.getValueFromKey(edgeKey, int) as int;
					var newEdge:GraphEdge = new GraphEdge();
					var source:GraphNode = _keyToNode[ idToNodeKey[idSource] ];
					var target:GraphNode = _keyToNode[ idToNodeKey[idTarget] ];
					
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
					source.addConnection(target);
					target.addConnection(source);
				}
			}
		}
		
		/**
		 * Set all of the positions to random values and zero the velocities.
		 */
		public function resetAllNodes():void
		{
			var i:int = 0;
			var length:int = 0;
			for each (var obj:* in _keyToNode) { ++length; }
			
			outputBounds.reset();
			var spacing:Number = 2 * Math.PI / (length + 1);
			var angle:Number = 0;
			var xMax:Number = _allowedBounds.getXMax();
			var yMax:Number = _allowedBounds.getYMax();
			for each (var node:GraphNode in _keyToNode)
			{
				if (node == null)
				{
					trace('empty element in _idToNode');
					continue;
				}
				var x:Number = Math.cos(angle);
				var y:Number = Math.sin(angle);
				node.position.x = xMax * x; 
				node.position.y = yMax * y;
				angle += spacing;
				outputBounds.includePoint(node.position);
				
				node.velocity.x = 0;
				node.velocity.y = 0;
			}
			
			_spatialCallbacks.triggerCallbacks();
			getCallbackCollection(this).triggerCallbacks();
		}
		
		private function handleColumnsChange():void
		{
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
			
			repulsionConstant.value = (100*100) / _numNodes;
			attractionConstant.value = 1 / Math.sqrt(repulsionConstant.value);
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
			var distanceSq:Number = dx2 + dy2;
			var distance:Number = Math.sqrt(distanceSq);
			var forceMagnitude:Number = distance * attractionConstant.value; 
			var forceX:Number;
			var forceY:Number;
			if (distance > 1)
			{
				forceX = forceMagnitude * dx / distance;
				forceY = forceMagnitude * dy / distance;
			}
			else
			{
				forceX = 0;
				forceY = 0;
			}
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
			var distance:Number = Math.sqrt(resultantVectorMagnitude);
  			var forceMagnitude:Number;
			var forceX:Number;
			var forceY:Number;
			if (distance > 1)
			{
				forceMagnitude = repulsionConstant.value / resultantVectorMagnitude;
				forceX = forceMagnitude * dx / distance;
				forceY = forceMagnitude * dy / distance;
			}
			else
			{
				forceX = repulsionConstant.value;
				forceY = repulsionConstant.value;
			}
			output.x = forceX;
			output.y = forceY;
			return output;
		}
		
		//private const _
		/**
		 * Update the positions of the nodes using a force directed layout.
		 */
		private function forceDirected(keys:Array = null):void
		{
			if (keys == null)
				keys = nodesColumn.keys;
			
			// if we should stop iterating
			if (shouldStop.value == true)
			{
				shouldStop.value = false;
				algorithmRunning.value = false;
				_spatialCallbacks.triggerCallbacks();
				_iterations = maxIterations.value;
				return;
			}
			
			DebugTimer.begin();
			

			algorithmRunning.value = true;
			var currentNode:GraphNode;
			var reachedEquilibrium:Boolean = false;
			var kineticEnergy:Number = 0;
			var key:IQualifiedKey;
			_nextIncrement += (_nextIncrement == _iterations) ? drawIncrement.value : 0;
			for (; _iterations < maxIterations.value; ++_iterations)
			{
				// if this function has run for more than 100ms, call later to finish
				if (StageUtils.shouldCallLater)
				{
					StageUtils.callLater(this, forceDirected, [keys], true);
					DebugTimer.end();
					return;
				}
				outputBounds.reset();
				for each (var obj:Object in keys)
				{
					key = obj as IQualifiedKey;
					currentNode = _keyToNode[key];
					netForce.x = 0;
					netForce.y = 0;
					
					// calculate edge attraction in connected nodes
					var connectedNodes:Vector.<GraphNode> = (_keyToNode[key] as GraphNode).connections;
					for each (var connectedNode:GraphNode in connectedNodes)
					{
						// if keys is a subset of nodesColumn.keys, we don't want to compute attraction of unselected nodes
						if (keys.indexOf(connectedNode.key) < 0)
							continue;
						
						var tempAttraction:Point = hookeAttraction(currentNode, connectedNode, tempPoint);
						netForce.x += tempAttraction.x;
						netForce.y += tempAttraction.y;
					}
					if (connectedNodes == null || connectedNodes.length == 0)
						continue;
					
					// calculate repulsion with every node except itself
					for each (var otherKey:Object in keys)
					{
						var otherNode:GraphNode = _keyToNode[otherKey];
						if (currentNode == otherNode) 
							continue;
						
						var tempRepulsion:Point = coulumbRepulsion(currentNode, otherNode, tempPoint);
						netForce.x += tempRepulsion.x;
						netForce.y += tempRepulsion.y;
					}
					
					// TODO: handle unconnected nodes (don't count their forces, but push them away)
					
					// calculate velocity
					currentNode.velocity.x = (currentNode.velocity.x + netForce.x) * (1 - dampingConstant.value);
					currentNode.velocity.y = (currentNode.velocity.y + netForce.y) * (1 - dampingConstant.value);
					
					// determine the next position (don't modify the current position because we need it for calculating KE
					currentNode.nextPosition.x = currentNode.position.x + currentNode.velocity.x;
					currentNode.nextPosition.y = currentNode.position.y + currentNode.velocity.y;
					outputBounds.includePoint(currentNode.nextPosition);
				}

				// calculate the KE, update positions, and shift allowedBounds
				var xSum:Number = 0;
				var ySum:Number = 0;
				kineticEnergy = 0;
				for each (key in keys)
				{
					currentNode = _keyToNode[key];
					var p1:Point = currentNode.position;
					var p2:Point = currentNode.nextPosition;
					kineticEnergy += ComputationalGeometryUtils.getDistanceFromPoint(p1.x, p1.y, p2.x, p2.y);
					p1.x = p2.x;
					p1.y = p2.y;
				}

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
				StageUtils.callLater(this, forceDirected, [keys], true);
			
			// trigger drawing callbacks
			getCallbackCollection(this).triggerCallbacks();
			
			algorithmRunning.value = false;
			DebugTimer.end();
		}
		
		/**
		 * Sets the output bounds.
		 */
		private function setOutputBounds():void
		{
			outputBounds.reset();
			for each (var node:GraphNode in _keyToNode)
			{
				outputBounds.includePoint(node.position);				
			}
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
		}

		// the iterations
		private var _iterations:int = 0;
		private var _nextIncrement:int = 0;

		
		// reusable objects
		private const netForce:Point = new Point(); // the force vector
		private const tempPoint:Point = new Point(); // temp point used for computing force 
		private var outputBounds:IBounds2D = new Bounds2D(); 
		private const edgesShape:Shape = new Shape(); 
	}
}