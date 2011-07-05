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
	import weave.utils.DebugTimer;
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
		// TODO change these to use QKeys instead
		private var _edges:Array = []; // list of edges
		private var _keyToNode:Array = [];  // IQualifiedKey-> GraphNode
		private var _keyToConnectedNodes:Object = []; // IQualifiedKey-> Array (of GraphNode objects)
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
		[Bindable] public var algorithms:Array = [ FORCE_DIRECTED, FADE ]; // choices
		public const currentAlgorithm:LinkableString = registerNonSpatialProperty(new LinkableString(FORCE_DIRECTED), changeAlgorithm); // the algorithm
		private var _algorithm:Function = null; // current algorithm function
		private static const FORCE_DIRECTED:String = "Force Directed";
		private static const FADE:String = "FADE";

		public const radius:LinkableNumber = registerSpatialProperty(new LinkableNumber(2)); // radius of the circles
		public const minimumEnergy:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.1)); // if less than this, close enough
		public const attractionConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.1)); // made up spring constant in hooke's law
		public const repulsionConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(1)); // coulumb's law constant
		public const dampingConstant:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(0.75)); // the amount of damping on the forces
		public const maxIterations:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(1000), handleIterations); // max iterations
		public const drawIncrement:LinkableNumber = registerNonSpatialProperty(new LinkableNumber(200)); // the number of iterations between drawPlot calls	
		public const shouldStop:LinkableBoolean = registerNonSpatialProperty(new LinkableBoolean(false)); // should the algorithm halt on the next iteration? 
		public const algorithmRunning:LinkableBoolean = registerNonSpatialProperty(new LinkableBoolean(false)); // is an algorithm running?
		
		private function handleIterations():void { }

		// FINISH THESE
		private function fade():IBounds2D
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
			var x:Number;
			var y:Number;
			
			// loop through each node and draw it
			for each (var key:IQualifiedKey in recordKeys)
			{
				var connections:Array = _keyToConnectedNodes[key];
				if (connections == null || connections.length == 0)
					continue;
				var node:GraphNode = _keyToNode[key];
				
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
			/*_currentDataBounds.copyFrom(dataBounds);
			_currentScreenBounds.copyFrom(screenBounds);

			var graphics:Graphics = tempShape.graphics;
			graphics.clear();
			
			graphics.lineStyle(1, 0x000000, .2);
						
			for each (var edge:GraphEdge in _edges)
			{
				var source:GraphNode = _idToNode[edge.source.id];
				var target:GraphNode = _idToNode[edge.target.id];

				var sourcePoint:Point = source.position;
				projectPoint(sourcePoint.x, sourcePoint.y);
				if (screenBounds.containsPoint(screenPoint) == false)
					continue;
				graphics.moveTo(screenPoint.x, screenPoint.y);

				var targetPoint:Point = target.position;
				projectPoint(targetPoint.x, targetPoint.y);
				if (screenBounds.containsPoint(screenPoint) == false)
					continue;
				graphics.lineTo(screenPoint.x, screenPoint .y);
			}
			
			destination.draw(tempShape, null, null, null, null, false);*/
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
					_keyToNode[nodesKeys[i]] = newNode;
				}
				nodesKeys = null;
			}
			
			// setup the edges array
			{ // force garbage collection
				/*var edgesKeys:Array = edgeSourceColumn.keys;
				for (i = 0; i < edgesKeys.length; ++i)
				{
					var edgeKey:IQualifiedKey = edgesKeys[i] as IQualifiedKey;
					var idSource:int = edgeSourceColumn.getValueFromKey(edgeKey, int) as int;
					var idTarget:int = edgeTargetColumn.getValueFromKey(edgeKey, int) as int;
					var newEdge:GraphEdge = new GraphEdge();
					var source:GraphNode = _keyToNode[];
					var target:GraphNode = _keyToNode[idTarget];
					
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
				}*/
			}
		}
		
		/**
		 * Set all of the positions to random values and zero the velocities.
		 */
		private function resetAllNodes():void
		{
			var i:int = 0;
			var length:int = 0;
			for each (var obj:* in _keyToNode) { ++length; }
			
			_allowedBounds.setBounds(-100, -100, 100, 100);
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
		}
		
		private function handleColumnsChange():void
		{
			_keyToNode.length = 0;
			_keyToConnectedNodes.length = 0;
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
			var forceMagnitude:Number = distance * attractionConstant.value; 
			
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
			
			DebugTimer.begin();
			
			repulsionConstant.value = (100*100) / _keyToNode.length;
			attractionConstant.value = 1 / Math.sqrt(repulsionConstant.value);
			algorithmRunning.value = true;
			var currentNode:GraphNode;
			var reachedEquilibrium:Boolean = false;
			var kineticEnergy:Number = 0;
			
			_nextIncrement += (_nextIncrement == _iterations) ? drawIncrement.value : 0;
			var iterationsDelayed:Boolean = false;
			for (; _iterations < maxIterations.value; ++_iterations)
			{
				// if this function has run for more than 100ms, call later to finish
				if (StageUtils.shouldCallLater)
				{
					StageUtils.callLater(this, forceDirected, null, true);
					DebugTimer.end();
					return;
				}
				outputBounds.reset();
				for (var obj:Object in _keyToNode)
				{
					var key:IQualifiedKey = obj as IQualifiedKey;
					netForce.x = 0;
					netForce.y = 0;
					
					// calculate edge attraction in connected nodes
					var connectedNodes:Array = _keyToConnectedNodes[key];
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
					for each (var otherNode:GraphNode in _keyToNode)
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
					
					// calculate velocity
					currentNode.velocity.x = (currentNode.velocity.x + netForce.x) * dampingConstant.value;
					currentNode.velocity.y = (currentNode.velocity.y + netForce.y) * dampingConstant.value;
					
					// determine the next position (don't modify the current position because we need it for calculating KE
					currentNode.nextPosition.x = currentNode.position.x + currentNode.velocity.x;
					currentNode.nextPosition.y = currentNode.position.y + currentNode.velocity.y;
					outputBounds.includePoint(currentNode.nextPosition);
					//_allowedBounds.constrainPoint(currentNode.nextPosition);
				}

				// calculate the KE, update positions, and shift allowedBounds
				var xSum:Number = 0;
				var ySum:Number = 0;
				kineticEnergy = 0;
				for each (currentNode in _keyToNode)
				{
					var p1:Point = currentNode.position;
					var p2:Point = currentNode.nextPosition;
					kineticEnergy += ComputationalGeometryUtils.getDistanceFromPoint(p1.x, p1.y, p2.x, p2.y);

					p1.x = p2.x;
					p1.y = p2.y;
				}
				/*_allowedBounds.setCenteredRectangle(
							outputBounds.getXCenter(),
							outputBounds.getYCenter(),
							100, 100);*/
				
				
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
		
		// reusable objects
		private const netForce:Point = new Point(); // the force vector
		private const tempPoint:Point = new Point(); // temp point used for computing force 
		private var outputBounds:IBounds2D = new Bounds2D(); 
	}
}