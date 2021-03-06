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

package weave.data.BinningDefinitions
{
	import weave.api.WeaveAPI;
	import weave.api.core.ILinkableHashMap;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IBinningDefinition;
	import weave.api.data.IColumnWrapper;
	import weave.api.data.IPrimitiveColumn;
	import weave.api.newLinkableChild;
	import weave.compiler.MathLib;
	import weave.core.LinkableNumber;
	import weave.data.AttributeColumns.StringColumn;
	import weave.data.BinClassifiers.NumberClassifier;
	
	/**
	 * Divides a data range into a number of equally spaced bins.
	 * 
	 * @author adufilie
	 * @author abaumann
	 */
	public class SimpleBinningDefinition implements IBinningDefinition
	{
		public function SimpleBinningDefinition()
		{
			// we need a default value for the number of bins (in the spirit of a micro API).
			numberOfBins.value = 10;
		}
		
		/**
		 * numberOfBins
		 * The number of bins to generate when calling deriveExplicitBinningDefinition().
		 */
		public const numberOfBins:LinkableNumber = newLinkableChild(this, LinkableNumber);

		/**
		 * deriveExplicitBinningDefinition
		 * From this simple definition, derive an explicit definition.
		 */
		public function getBinClassifiersForColumn(column:IAttributeColumn, output:ILinkableHashMap):void
		{
			var name:String;
			// clear any existing bin classifiers
			output.removeAllObjects();
			
			var nonWrapperColumn:IAttributeColumn = column;
			while (nonWrapperColumn is IColumnWrapper)
				nonWrapperColumn = (nonWrapperColumn as IColumnWrapper).internalColumn;
			
			var integerValuesOnly:Boolean = nonWrapperColumn is StringColumn;
			var dataMin:Number = WeaveAPI.StatisticsCache.getMin(column);
			var dataMax:Number = WeaveAPI.StatisticsCache.getMax(column);
			
			// stop if there is no data
			if (isNaN(dataMin))
				return;
		
			var binMin:Number;
			var binMax:Number = dataMin;
			var maxInclusive:Boolean;
			
			for (var iBin:int = 0; iBin < numberOfBins.value; iBin++)
			{
				if (integerValuesOnly)
				{
					maxInclusive = true;
					if (iBin == 0)
						binMin = dataMin;
					else
						binMin = binMax + 1;
					if (iBin == numberOfBins.value - 1)
						binMax = dataMax;
					else
						binMax = Math.floor(dataMin + (iBin + 1) * (dataMax - dataMin) / numberOfBins.value);
					// skip empty bins
					if (binMin > binMax)
						continue;
				}
				else
				{
					// classifiers use min <= value < max,
					// except for the final one, which uses min <= value <= max
					binMin = binMax;
					if (iBin == numberOfBins.value - 1)
					{
						binMax = dataMax;
						maxInclusive = true;
					}
					else
					{
						maxInclusive = false;
						binMax = dataMin + (iBin + 1) * (dataMax - dataMin) / numberOfBins.value;
						// TEMPORARY SOLUTION -- round bin boundaries
						binMax = MathLib.roundSignificant(binMax, 4);
					}
					
					// TEMPORARY SOLUTION -- round bin boundaries
					if (iBin > 0)
						binMin = MathLib.roundSignificant(binMin, 4);
	
					// skip bins with no values
					if (binMin == binMax && !maxInclusive)
						continue;
				}
				tempNumberClassifier.min.value = binMin;
				tempNumberClassifier.max.value = binMax;
				tempNumberClassifier.minInclusive.value = true;
				tempNumberClassifier.maxInclusive.value = maxInclusive;

				name = tempNumberClassifier.generateBinLabel(nonWrapperColumn as IPrimitiveColumn);
				output.copyObject(name, tempNumberClassifier);
			}
		}
		
		// reusable temporary object
		private static const tempNumberClassifier:NumberClassifier = new NumberClassifier();
	}
}
