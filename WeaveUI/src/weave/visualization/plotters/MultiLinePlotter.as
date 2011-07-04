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
	import flash.display.Graphics;
	import flash.display.Shape;
	import flash.geom.Point;
	
	import weave.api.data.IQualifiedKey;
	import weave.api.primitives.IBounds2D;
	import weave.core.LinkableString;
	import weave.data.AttributeColumns.AlwaysDefinedColumn;
	import weave.data.AttributeColumns.DynamicColumn;
	import weave.primitives.Bounds2D;
	import weave.utils.ColumnUtils;
	import weave.visualization.plotters.styles.DynamicLineStyle;
	import weave.visualization.plotters.styles.SolidLineStyle;

	/**
	 * This plotter plots lines using x1,y1,x2,y2 values.
	 * There is a set of data coordinates and a set of screen offset coordinates.
	 * 
	 * @author adufilie
	 */
	public class MultiLinePlotter extends AbstractPlotter
	{
		public function MultiLinePlotter()
		{
			registerSpatialProperties(x1Data, y1Data, x2Data, y2Data);
			registerNonSpatialProperties(x1ScreenOffset, y1ScreenOffset, x2ScreenOffset, y2ScreenOffset, lineStyle);
			// initialize default line style
			lineStyle.requestLocalObject(SolidLineStyle, false);
			
			curveType.value = CURVE_FROM_STARTING_POINT;
		}

		public static const CURVE_FROM_STARTING_POINT:String = "CURVE_FROM_STARTING_POINT";
		public static const CURVE_TOWARD_END_POINT:String    = "CURVE_TOWARD_END_POINT";
		public static const CURVE_TO_MIDDLE:String     		 = "CURVE_TO_MIDDLE";
		public static const NO_CURVE:String           		 = "NO_CURVE";

		// spatial properties
		/**
		 * This is the beginning X data value associated with the line.
		 */
		public const x1Data:DynamicColumn = new DynamicColumn();
		/**
		 * This is the beginning Y data value associated with the line.
		 */
		public const y1Data:DynamicColumn = new DynamicColumn();
		/**
		 * This is the ending X data value associated with the line.
		 */
		public const x2Data:DynamicColumn = new DynamicColumn();
		/**
		 * This is the ending Y data value associated with the line.
		 */
		public const y2Data:DynamicColumn = new DynamicColumn();

		// visual properties
		/**
		 * This is an offset in screen coordinates when projecting the line onto the screen.
		 */
		public const x1ScreenOffset:AlwaysDefinedColumn = new AlwaysDefinedColumn(0);
		/**
		 * This is an offset in screen coordinates when projecting the line onto the screen.
		 */
		public const y1ScreenOffset:AlwaysDefinedColumn = new AlwaysDefinedColumn(0);
		/**
		 * This is an offset in screen coordinates when projecting the line onto the screen.
		 */
		public const x2ScreenOffset:AlwaysDefinedColumn = new AlwaysDefinedColumn(0);
		/**
		 * This is an offset in screen coordinates when projecting the line onto the screen.
		 */
		public const y2ScreenOffset:AlwaysDefinedColumn = new AlwaysDefinedColumn(0);
		/**
		 * This is the line style used to draw the line.
		 */
		public const lineStyle:DynamicLineStyle = new DynamicLineStyle();

		/**
		 * This is a flag to set to cause the line to be drawn as a curve instead
		 */
		public const curveType:LinkableString = new LinkableString();
	
		/**
		 * This function returns a Bounds2D object set to the data bounds associated with the given record key.
		 * @param key The key of a data record.
		 * @param outputDataBounds A Bounds2D object to store the result in.
		 */
		override public function getDataBoundsFromRecordKey(recordKey:IQualifiedKey):Array
		{
			var b1:IBounds2D = getReusableBounds();
			var b2:IBounds2D = getReusableBounds();
			b1.includeCoords(
					x1Data.getValueFromKey(recordKey, Number),
					y1Data.getValueFromKey(recordKey, Number)
				);
			b2.includeCoords(
					x2Data.getValueFromKey(recordKey, Number),
					y2Data.getValueFromKey(recordKey, Number)
				);
			return [b1,b2];
		}

		/**
		 * Draws the graphics onto a sprite.
		 * @param sprite The sprite to draw the graphics onto.
		 * @param zoomView This defines how to project data coordinates to screen coordinates.
		 * @param displayProperties This defines line and fill properties 
		 * @param filter An optional set of keys for shapes to draw.
		 */
		private var _xyDataColumns:Array = [];
		protected function addPointOnLine(xDataColumn:DynamicColumn, yDataColumn:DynamicColumn, startAsNewLine:Boolean = false):void
		{
			_xyDataColumns.push( {x:xDataColumn, y:yDataColumn, newLine:startAsNewLine} );
		}
		 
		private var _prevX:Number = 0;
		private var _prevY:Number = 0;
		
		/**
		 * This function may be defined by a class that extends AbstractPlotter to use the basic template code in AbstractPlotter.drawPlot().
		 */
		override protected function addRecordGraphicsToTempShape(recordKey:IQualifiedKey, dataBounds:IBounds2D, screenBounds:IBounds2D, tempShape:Shape):void
		{
			var controlPointY:Number = 0;
			
			// draw graphics
			var graphics:Graphics = tempShape.graphics;
			
			lineStyle.beginLineStyle(recordKey, graphics);				
			
			for (var i:int = 0; i < _xyDataColumns.length; i++) 
			{
				// project data coordinates to screen coordinates and draw graphics
				tempPoint.x = ColumnUtils.getNorm(_xyDataColumns[i].x, recordKey);
				tempPoint.y = ColumnUtils.getNorm(_xyDataColumns[i].y, recordKey);
				
				dataBounds.projectPointTo(tempPoint, screenBounds);				
				var x:Number = tempPoint.x;
				var y:Number = tempPoint.y;
				if (i == 0){
					graphics.moveTo(x, y);
				} 
				else{
					switch(curveType.value.toUpperCase())
					{
						// control point is at the y location of the start of the line (the previous dimension drawn), so it arcs from the previous point
						case CURVE_FROM_STARTING_POINT:
							controlPointY = _prevY;
							break;
						
						// control point is at the y location of the end of the line (the next dimension to draw), so it arcs toward the next point
						case CURVE_TOWARD_END_POINT:
							controlPointY = y;
							break;
						
						// all control points at the middle of the visualization vertical space
						case CURVE_TO_MIDDLE:
							controlPointY = screenBounds.getYCenter();
							break;
					}
					
					// if we don't want to curve (lines), or there is no slope change to next dimension, then draw line.
					if(curveType.value.toUpperCase() == NO_CURVE || (_prevY == y) )
					{
						graphics.lineTo(x, y);
					}
					else
						graphics.curveTo(_prevX + (x - _prevX)/4, controlPointY, x, y);
					
					// debugging control point
					/*graphics.drawCircle(_prevX + (x - _prevX)/4, controPointY, 2);
					graphics.moveTo(x, y);*/
				}
				
				_prevX = x;
				_prevY = y;
			}
			
			lineStyle.beginLineStyle(recordKey, graphics);				
			
			// project data coordinates to screen coordinates and draw graphics
			tempPoint.x = x1Data.getValueFromKey(recordKey, Number);
			tempPoint.y = y1Data.getValueFromKey(recordKey, Number);
			dataBounds.projectPointTo(tempPoint, screenBounds);
			tempPoint.x += x1ScreenOffset.getValueFromKey(recordKey, Number);
			tempPoint.y += y1ScreenOffset.getValueFromKey(recordKey, Number);

			graphics.moveTo(tempPoint.x, tempPoint.y);
			
			tempPoint.x = x2Data.getValueFromKey(recordKey, Number);
			tempPoint.y = y2Data.getValueFromKey(recordKey, Number);
			dataBounds.projectPointTo(tempPoint, screenBounds);
			tempPoint.x += x2ScreenOffset.getValueFromKey(recordKey, Number);
			tempPoint.y += y2ScreenOffset.getValueFromKey(recordKey, Number);
			
			graphics.lineTo(tempPoint.x, tempPoint.y);
		}
		
		private static const tempPoint:Point = new Point(); // reusable object
	}
}
