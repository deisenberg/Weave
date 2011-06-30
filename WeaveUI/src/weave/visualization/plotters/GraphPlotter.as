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
			//var fill:SolidFillStyle = fillStyle.requestLocalObject(SolidFillStyle, false);
			//fill.color.internalDynamicColumn.requestGlobalObject(Weave.DEFAULT_COLOR_COLUMN, ColorColumn, false);
			
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
		private var _edges:Object = []; // list of edges
		private var _idToNode:Object = [];  // int -> GraphNode
		private var _idToConnectedNodes:Object = []; // int -> Array (of GraphNode objects)
		
		// styles
		public const lineStyle:DynamicLineStyle = newNonSpatialProperty(DynamicLineStyle);
		//public const fillStyle:SolidFillStyle = newNonSpatialProperty(SolidFillStyle);
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

		public const positionBounds:LinkableBounds2D = registerNonSpatialProperty(new LinkableBounds2D()); 
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
		
		private var _radii:Object;
		private var _radialCenter:Point;
		private function radial():IBounds2D
		{
			outputBounds.reset();
			
			algorithmRunning.value = true;
			var currentNode:GraphNode;

			var nodes:Array = (_idToNode as Array).concat();
			nodes.sort(handleNodeSort);
			var idToVisitedNodes:Array = [];
			var idToLevel:Array = []; // lower level => larger radius
			var currentLevel:int = 0;			

			var sourceNode:GraphNode = (nodes as Array).shift(); 
			sourceNode.position.x = 0;
			sourceNode.position.y = 0;
			_radialCenter = sourceNode.position;
			(nodes as Array).unshift(sourceNode);
			idToLevel[sourceNode.id] = currentLevel;

			var r:Number = 0;
			var radiusIncrement:Number = radius.value + 1;
			var queue:Array = [];
			queue.push(sourceNode);
			while (queue.length > 0)
			{
				var target:GraphNode;				
				currentNode = queue.shift();
				var xCurrent:Number = currentNode.position.x;
				var yCurrent:Number = currentNode.position.y;
				var connectedNodes:Array = _idToConnectedNodes[currentNode.id];
				if (connectedNodes == null || connectedNodes.length == 0)
					continue;

				var connectedNodesLength:Number = 0;
				for each (target in connectedNodes)
				{
					if (idToVisitedNodes[target.id] == null)
						connectedNodesLength++;
				}
				r = connectedNodesLength * radiusIncrement;
				
				var angleSpacing:Number = 2 * Math.PI / connectedNodesLength;
				var angle:Number = 0;
				for each (target in connectedNodes)
				{
					if (idToVisitedNodes[target.id] == null)
					{
						queue.push(target);
						idToVisitedNodes[target.id] = true;
						target.position.x = xCurrent + r * Math.cos(angle);
						target.position.y = yCurrent + r * Math.sin(angle);
						outputBounds.includePoint(target.position);				
					}
					angle += angleSpacing;
				}
			}
			
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
			positionBounds.copyFrom(outputBounds);

			// rebuild spatial index
			_spatialCallbacks.triggerCallbacks();
			
			// trigger drawing callbacks
			getCallbackCollection(this).triggerCallbacks();
			
			algorithmRunning.value = false;
			return outputBounds;
		}
		
		// FINISH THIS
		private function fade():IBounds2D
		{
			// if we should stop iterating
			if (shouldStop.value == true)
			{
				shouldStop.value = false;
				algorithmRunning.value = false;
				_spatialCallbacks.triggerCallbacks();
				return outputBounds;
			}

			outputBounds.reset();
			algorithmRunning.value = true;
			var currentNode:GraphNode;
			var reachedEquilibrium:Boolean = false;
			var kineticEnergy:Number = 0;
			var damping:Number = 0.25;
			
			var tempDistance:Number;
			_nextIncrement += drawIncrement.value;
			var iterationsDelayed:Boolean = false;
			for (; _iterations < maxIterations.value; ++_iterations)
			{
				// if this function has run for more than 100ms, call later to finish
				if (StageUtils.shouldCallLater)
				{
					StageUtils.callLater(this, _algorithm, null, true);
					//trace('callLater: ', _iterations);
					return outputBounds;
				}
				
				/*_repulsionCache = new Dictionary();
				_attractionCache = new Dictionary();*/
				for each (currentNode in _idToNode)
				{
					netForce.x = 0;
					netForce.y = 0;
					
					// calculate edge attraction in connected nodes
					var connectedNodes:Array = _idToConnectedNodes[currentNode.id];
					for each (var connectedNode:GraphNode in connectedNodes)
					{
						var tempAttraction:Point = hookeAttraction(currentNode, connectedNode, tempPoint);
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
						netForce.x += tempRepulsion.x;
						netForce.y += tempRepulsion.y;
					}
					
					// TODO: handle unconnected nodes (don't count their forces, but push them away)
					
					// trace(currentNode.id, '\t', netForce.x, netForce.y);
					
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
			for each (currentNode in _idToNode)
			{
				outputBounds.includePoint(currentNode.position);				
			}
			
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
			positionBounds.copyFrom(outputBounds);

			// if we reached equilibrium, rebuild the spatial index
			if (reachedEquilibrium == true || _iterations >= maxIterations.value)
				_spatialCallbacks.triggerCallbacks();
			else // or call later to finish
				StageUtils.callLater(this, _algorithm, null, true);
			
			// trigger drawing callbacks
			getCallbackCollection(this).triggerCallbacks();
			
			algorithmRunning.value = false;
			return outputBounds;
		}
		private function incremental():void { }

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

			/*if (_algorithm == radial)
			{
				drawRadialBackground(dataBounds, screenBounds, destination);
				return;
			}*/
			
			var graphics:Graphics = tempShape.graphics;
			graphics.clear();
			
			graphics.beginFill(0xFF0000, 1);
			graphics.lineStyle(1, 0x000000, .2);
						
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
			
			graphics.endFill();
			destination.draw(tempShape, null, null, null, null, false);
		}

		private function drawRadialBackground(dataBounds:IBounds2D, screenBounds:IBounds2D, destination:BitmapData):void
		{
			var graphics:Graphics = tempShape.graphics;
			graphics.clear();
			
			graphics.lineStyle(1, 0x000000, 0.1);

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
			
			// now draw concentric circles
			if (_radii != null)
			{
				graphics.lineStyle(1, 0x111111, 0.8, false, LineScaleMode.NONE);
				var xCenterData:Number = _radialCenter.x;
				var yCenterData:Number = _radialCenter.y;
				projectPoint(xCenterData, yCenterData);
				var xCenterScreen:Number = screenPoint.x;
				var yCenterScreen:Number = screenPoint.y;
				for each (var radius:Number in _radii)
				{
					projectPoint(xCenterData + radius, yCenterData);
					var x:Number = screenPoint.x;
					var y:Number = screenPoint.y;
					var dx:Number = x - xCenterScreen;
					var dy:Number = y - yCenterScreen;
					graphics.drawCircle(xCenterScreen, yCenterScreen, Math.sqrt(dx*dx + dy*dy));
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
					if (source == target)
					{
						trace('cannot have nodes connected to themselves');
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
					trace('here');
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


		private function cachedLookup(dictionary:Dictionary, a:GraphNode, b:GraphNode):Point
		{
			if (dictionary[a] == undefined)
			{
				dictionary[a] = new Dictionary();
				return null;
			}
			
			var returnValue:Point = dictionary[a][b];
			if (returnValue != null)
				return returnValue;
			
			if (dictionary[b] == undefined)
			{
				dictionary[b] = new Dictionary();
				return null;
			}
			
			returnValue = dictionary[b][a];
			if (returnValue == null)
				return null;
			returnValue = returnValue.clone();
			returnValue.x = 0 - returnValue.x;
			returnValue.y = 0 - returnValue.y;
			return returnValue;
		}
		private function cachedSet(dictionary:Dictionary, a:GraphNode, b:GraphNode, leftPoint:Point):void
		{
			if (dictionary[a] == undefined)
				dictionary[a] = new Dictionary();
			if (dictionary[b] == undefined)
				dictionary[b] = new Dictionary();
			
			var rightPoint:Point = new Point();
			rightPoint.x = 0 - leftPoint.x;
			rightPoint.y = 0 - leftPoint.y;
			dictionary[a][b] = leftPoint;
			dictionary[b][a] = rightPoint;
		}
		
		private function hookeAttraction(a:GraphNode, b:GraphNode, output:Point = null):Point
		{
			//var cachedPoint:Point = cachedLookup(_attractionCache, a, b);
			//if (cachedPoint)
			//	return cachedPoint;

			if (!output) 
				output = new Point();
			
			var dx:Number = b.position.x - a.position.x;
			var dy:Number = b.position.y - a.position.y;
			var dx2:Number = dx * dx;
			var dy2:Number = dy * dy;			
			var distance:Number = Math.sqrt(dx2 + dy2);
			var forceMagnitude:Number = attractionConstant.value * (distance - nodeSeparation.value); 
			
			output.x = forceMagnitude * dx / distance;
			output.y = forceMagnitude * dy / distance;

			//trace( a.node.id,', ', b.node.id, ', ', output.x, ', ', output.y);
			//cachedSet(_attractionCache, a, b, output);
			return output; 
		}
		private function coulumbRepulsion(a:GraphNode, b:GraphNode, output:Point = null):Point
		{
			//var cachedPoint:Point = cachedLookup(_repulsionCache, a, b);
			//if (cachedPoint)
			//	return cachedPoint;
			
			if (!output) 
				output = new Point();
			
			var dx:Number = a.position.x - b.position.x;
			var dy:Number = a.position.y - b.position.y;
			var dx2:Number = dx * dx;
			var dy2:Number = dy * dy;			
			var resultantVectorMagnitude:Number = dx2 + dy2;
			var distance:Number = Math.sqrt(resultantVectorMagnitude);
			var forceMagnitude:Number = repulsionConstant.value / resultantVectorMagnitude; 
			
			output.x = forceMagnitude * dx / distance;
			output.y = forceMagnitude * dy / distance;

			//trace( a.node.id,', ', b.node.id, ', ', output.x, ', ', output.y);
			//cachedSet(_repulsionCache, a, b, output);
			return output;
		}
		private var _repulsionCache:Dictionary;
		private var _attractionCache:Dictionary;
		private function forceDirected():IBounds2D
		{
			// if we should stop iterating
			if (shouldStop.value == true)
			{
				shouldStop.value = false;
				algorithmRunning.value = false;
				_spatialCallbacks.triggerCallbacks();
				return outputBounds;
			}

			outputBounds.reset();
			algorithmRunning.value = true;
			var currentNode:GraphNode;
			var reachedEquilibrium:Boolean = false;
			var kineticEnergy:Number = 0;
			var damping:Number = 0.25;
			
			var tempDistance:Number;
			_nextIncrement += drawIncrement.value;
			var iterationsDelayed:Boolean = false;
			for (; _iterations < maxIterations.value; ++_iterations)
			{
				// if this function has run for more than 100ms, call later to finish
				if (StageUtils.shouldCallLater)
				{
					StageUtils.callLater(this, _algorithm, null, true);
					//trace('callLater: ', _iterations);
					return outputBounds;
				}
				
				/*_repulsionCache = new Dictionary();
				_attractionCache = new Dictionary();*/
				for each (currentNode in _idToNode)
				{
					netForce.x = 0;
					netForce.y = 0;
					
					// calculate edge attraction in connected nodes
					var connectedNodes:Array = _idToConnectedNodes[currentNode.id];
					for each (var connectedNode:GraphNode in connectedNodes)
					{
						var tempAttraction:Point = hookeAttraction(currentNode, connectedNode, tempPoint);
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
						netForce.x += tempRepulsion.x;
						netForce.y += tempRepulsion.y;
					}
					
					// TODO: handle unconnected nodes (don't count their forces, but push them away)
					
					// trace(currentNode.id, '\t', netForce.x, netForce.y);
					
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
			for each (currentNode in _idToNode)
			{
				outputBounds.includePoint(currentNode.position);				
			}
			
			outputBounds.centeredResize(1.25 * outputBounds.getWidth(), 1.25 * outputBounds.getHeight());
			positionBounds.copyFrom(outputBounds);

			// if we reached equilibrium, rebuild the spatial index
			if (reachedEquilibrium == true || _iterations >= maxIterations.value)
				_spatialCallbacks.triggerCallbacks();
			else // or call later to finish
				StageUtils.callLater(this, _algorithm, null, true);
			
			// trigger drawing callbacks
			getCallbackCollection(this).triggerCallbacks();
			
			algorithmRunning.value = false;
			return outputBounds;
		}
		
		// reusable objects
		private const netForce:Point = new Point(); // the force vector
		private const tempPoint:Point = new Point(); // temp point used for computing force 
		private var outputBounds:IBounds2D = new Bounds2D(); 
	}
}