/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1/GPL 2.0/LGPL 2.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is the Weave API.
 *
 * The Initial Developer of the Original Code is the Institute for Visualization
 * and Perception Research at the University of Massachusetts Lowell.
 * Portions created by the Initial Developer are Copyright (C) 2008-2011
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *
 * Alternatively, the contents of this file may be used under the terms of
 * either the GNU General Public License Version 2 or later (the "GPL"), or
 * the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
 * in which case the provisions of the GPL or the LGPL are applicable instead
 * of those above. If you wish to allow use of your version of this file only
 * under the terms of either the GPL or the LGPL, and not to allow others to
 * use your version of this file under the terms of the MPL, indicate your
 * decision by deleting the provisions above and replace them with the notice
 * and other provisions required by the GPL or the LGPL. If you do not delete
 * the provisions above, a recipient may use your version of this file under
 * the terms of any one of the MPL, the GPL or the LGPL.
 *
 * ***** END LICENSE BLOCK ***** */

package weave.api.primitives
{
	import flash.geom.Point;
	import flash.geom.Rectangle;
	
	/**
	 * IBounds2D provides a flexible interface to a Rectangle-like object.
	 * The bounds values are stored as xMin,yMin,xMax,yMax instead of x,y,width,height
	 * because information is lost when storing as width,height and it causes rounding
	 * errors when using includeBounds() & includePoint(), depending on the order you
	 * include multiple points.
	 * 
	 * @author adufilie
	 */
	public interface IBounds2D
	{
		/**
		 * These are the values defining the bounds.
		 */
		function getXMin():Number;
		function getYMin():Number;
		function getXMax():Number;
		function getYMax():Number;
		
		function setXMin(value:Number):void;
		function setYMin(value:Number):void;
		function setXMax(value:Number):void;
		function setYMax(value:Number):void;

		/**
		 * This function copies the bounds from another IBounds2D object.
		 * @param A IBounds2D object to copy the bounds from.
		 */
		function copyFrom(other:IBounds2D):void;
		
		/**
		 * This function makes a copy of the IBounds2D object.
		 * @return An equivalent copy of this IBounds2D object.
		 */
		function cloneBounds():IBounds2D;

		/**
		 * For the x and y dimensions, this function swaps min and max values if min > max.
		 */
		function makeSizePositive():void;
		
		/**
		 * This function resets all coordinates to NaN.
		 */
		function reset():void;
		
		/**
		 * This function checks if any coordinates are undefined or infinite.
		 * @return true if any coordinate is not a finite number.
		 */
		function isUndefined():Boolean;
		
		/**
		 * This function checks if the IBounds2D is empty.
		 * @return true if the width or height is 0, or is undefined.
		 */
		function isEmpty():Boolean;
		
		/**
		 * This function compares the IBounds2D with another IBounds2D.
		 * @param other Another IBounds2D to compare to
		 * @return true if given IBounds2D is equivalent, even if values are undefined
		 */
		function equals(other:IBounds2D):Boolean;
		
		/**
		 * This function sets the four coordinates that define the bounds.
		 * @param xMin The new xMin value.
		 * @param yMin The new yMin value.
		 * @param xMax The new xMax value.
		 * @param yMax The new yMax value.
		 */
		function setBounds(xMin:Number, yMin:Number, xMax:Number, yMax:Number):void;

		/**
		 * This function sets the bounds coordinates using x, y, width and height values.
		 * @param x The new xMin value.
		 * @param y The new yMin value.
		 * @param width The new width of the bounds.
		 * @param height The new height of the bounds.
		 */
		function setRectangle(x:Number, y:Number, width:Number, height:Number):void;
		
		/**
		 * This function copies the values from this IBounds2D object into a Rectangle object.
		 * @param output A Rectangle to store the result in.
		 * @param makeSizePositive If true, this will give the Rectangle positive width/height values.
		 * @return Either the given output Rectangle, or a new Rectangle if none was specified.
		 */
		function getRectangle(output:Rectangle = null, makeSizePositive:Boolean = true):Rectangle;

		/**
		 * This function will expand this IBounds2D to include a point.
		 * @param newPoint A point to include in this IBounds2D.
		 */
		function includePoint(newPoint:Point):void;

		/**
		 * This function will expand this IBounds2D to include a point.
		 * @param newX The X coordinate of a point to include in this IBounds2D.
		 * @param newY The Y coordinate of a point to include in this IBounds2D.
		 */
		function includeCoords(newX:Number, newY:Number):void;
		
		/**
		 * This function will expand this IBounds2D to include another IBounds2D.
		 * @param otherBounds Another IBounds2D object to include within this IBounds2D.
		 */
		function includeBounds(otherBounds:IBounds2D):void;

		// this function supports comparisons of bounds with negative width/height
		function overlaps(other:IBounds2D, includeEdges:Boolean = true):Boolean;


		/**
		 * This function supports a IBounds2D object having negative width & height, unlike the Rectangle object
		 * @param point A point to test.
		 * @return A value of true if the point is contained within this IBounds2D.
		 */
		function containsPoint(point:Point):Boolean;
		
		/**
		 * This function supports a IBounds2D object having negative width & height, unlike the Rectangle object
		 * @param x An X coordinate for a point.
		 * @param y A Y coordinate for a point.
		 * @return A value of true if the point is contained within this IBounds2D.
		 */
		function contains(x:Number, y:Number):Boolean;
		
		/**
		 * This function supports a IBounds2D object having negative width & height, unlike the Rectangle object
		 * @param other Another IBounds2D object to check.
		 * @return A value of true if the other IBounds2D is contained within this IBounds2D.
		 */
		function containsBounds(other:IBounds2D):Boolean;

		/**
		 * Grid numbers correspond to boxes in the following grid:
		 *     7 | 6 | 5
		 *     --+---+--
		 *     8 | 0 | 4
		 *     --+---+--
		 *     1 | 2 | 3
		 * If an x,y point is contained in box 0, it is contained in the IBounds2D object.
		 * For example, if a point is contained in box 2, x is within the x-range and y < y-range.
		 * @param x The x-coordinate to test for grid containment.
		 * @param y The y-coordinate to test for grid containment.
		 * @return The grid number from 0 to 8 that the x,y point is contained in, or NaN if none.
		 */
		function getGridContainment(x:Number, y:Number):Number;
		
		/**
		 * This function projects the coordinates of a Point object from this bounds to a
		 * destination bounds.
		 * @param point The Point object containing coordinates to project.
		 * @param toBounds The destination bounds.
		 */
		function projectPointTo(point:Point, toBounds:IBounds2D):void;
		
		/**
		 * This function projects all four coordinates of a IBounds2D object from this bounds
		 * to a destination bounds.
		 * @param inputAndOutput A IBounds2D object containing coordinates to project.
		 * @param toBounds The destination bounds.
		 */		
		function projectCoordsTo(coords:IBounds2D, toBounds:IBounds2D):void;

		/**
		 * This constrains a point to be within this IBounds2D.
		 * @param point The point to constrain.
		 * @param preserveSlope A boolean indicating whether a point outside of the bounds
		 * should be constrained inside the bounds at a position which lies on a line from 
		 * the bounds center to the original point's location.
		 */
		function constrainPoint(point:Point, preserveSlope:Boolean = false):void;

		/**
		 * This constrains the center point of another IBounds2D to be overlapping the center of this IBounds2D.
		 * @param boundsToConstrain The IBounds2D objects to constrain.
		 */
		function constrainBoundsCenterPoint(boundsToConstrain:IBounds2D):void;

		/**
		 * This function will reposition a bounds such that for the x and y dimensions of this
		 * bounds and another bounds, at least one bounds will completely contain the other bounds.
		 * @param boundsToConstrain the bounds we want to constrain to be within this bounds
		 * @param preserveSize if set to true, width,height of boundsToConstrain will remain the same
		 */
		function constrainBounds(boundsToConstrain:IBounds2D, preserveSize:Boolean = true):void;

		function offset(xOffset:Number, yOffset:Number):void;

		function setXRange(xMin:Number, xMax:Number):void;
		
		function setYRange(yMin:Number, yMax:Number):void;
		
		function setCenteredXRange(xCenter:Number, width:Number):void;

		function setCenteredYRange(yCenter:Number, height:Number):void;

		function setCenteredRectangle(xCenter:Number, yCenter:Number, width:Number, height:Number):void;

		/**
		 * This function will set the width and height to the new values while keeping the
		 * center point constant.  This function works with both positive and negative values.
		 */
		function centeredResize(width:Number, height:Number):void;

		function getXCenter():Number;
		function setXCenter(xCenter:Number):void;
		
		function getYCenter():Number;
		function setYCenter(yCenter:Number):void;
		
		/**
		 * This function stores the xCenter and yCenter coordinates into a Point object.
		 * @param value The Point object to store the xCenter and yCenter coordinates in.
		 */
		function getCenterPoint(output:Point):Point;
		
		/**
		 * This function will shift the bounds coordinates so that the xCenter and yCenter
		 * become the coordinates in a specified Point object.
		 * @param value The Point object containing the desired xCenter and yCenter coordinates.
		 */
		function setCenterPoint(value:Point):void;
		
		/**
		 * This function will shift the bounds coordinates so that the xCenter and yCenter
		 * become the specified values.
		 * @param xCenter The desired value for xCenter.
		 * @param yCenter The desired value for yCenter.
		 */
		function setCenter(xCenter:Number, yCenter:Number):void;
		
		/**
		 * This function stores the xMin and yMin coordinates in a Point object. 
		 * @param output The Point to store the xMin and yMin coordinates in.
		 * @return The output Point object.
		 */		
		function getMinPoint(output:Point):Point;
		/**
		 * This function sets the xMin and yMin values from a Point object. 
		 * @param value The Point containing new xMin and yMin coordinates.
		 */		
		function setMinPoint(value:Point):void;

		/**
		 * This function stores the xMax and yMax coordinates in a Point object. 
		 * @param output The Point to store the xMax and yMax coordinates in.
		 * @return The output Point object.
		 */		
		function getMaxPoint(output:Point):Point;
		/**
		 * This function sets the xMax and yMax values from a Point object. 
		 * @param value The Point containing new xMax and yMax coordinates.
		 */		
		function setMaxPoint(value:Point):void;

		/**
		 * This function sets the xMin and yMin values.
		 * @param x The new xMin coordinate.
		 * @param y The new yMin coordinate.
		 */		
		function setMinCoords(x:Number, y:Number):void;
		/**
		 * This function sets the xMax and yMax values.
		 * @param x The new xMax coordinate.
		 * @param y The new yMax coordinate.
		 */		
		function setMaxCoords(x:Number, y:Number):void;
		
		/**
		 * This is equivalent to ObjectUtil.numericCompare(xMax, xMin)
		 */		
		function getXDirection():Number;
		
		/**
		 * This is equivalent to ObjectUtil.numericCompare(yMax, yMin)
		 */		
		function getYDirection():Number;

		/**
		 * The width of the bounds is defined as xMax - xMin.
		 */		
		function getWidth():Number;
		
		/**
		 * The height of the bounds is defined as yMax - yMin.
		 */		
		function getHeight():Number;

		/**
		 * This function will set the width by adjusting the xMin and xMax values relative to xCenter.
		 * @param value The new width value.
		 */
		function setWidth(value:Number):void;
		/**
		 * This function will set the height by adjusting the yMin and yMax values relative to yCenter.
		 * @param value The new height value.
		 */
		function setHeight(value:Number):void;

		/**
		 * Area is defined as the absolute value of width * height.
		 * @return The area of the bounds.
		 */		
		function getArea():Number;
		
		/**
		 * The xCoverage is defined as the absolute value of the width.
		 * @return The xCoverage of the bounds.
		 */
		function getXCoverage():Number;
		/**
		 * The yCoverage is defined as the absolute value of the height.
		 * @return The yCoverage of the bounds.
		 */
		function getYCoverage():Number;
		
		/**
		 * The xNumericMin is defined as the minimum of xMin and xMax.
		 * @return The numeric minimum x coordinate.
		 */
		function getXNumericMin():Number;
		/**
		 * The yNumericMin is defined as the minimum of yMin and yMax.
		 * @return The numeric minimum y coordinate.
		 */
		function getYNumericMin():Number;
		/**
		 * The xNumericMax is defined as the maximum of xMin and xMax.
		 * @return The numeric maximum x coordinate.
		 */
		function getXNumericMax():Number;
		/**
		 * The xNumericMax is defined as the maximum of xMin and xMax.
		 * @return The numeric maximum y coordinate.
		 */
		function getYNumericMax():Number;
	}
}
