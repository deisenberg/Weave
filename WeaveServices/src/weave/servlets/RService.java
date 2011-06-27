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

package weave.servlets;

import java.io.File;
import java.rmi.RemoteException;
import java.util.UUID;

import javax.servlet.ServletConfig;
import javax.servlet.ServletException;

import weave.beans.KMeansClusteringResult;
import weave.beans.HierarchicalClusteringResult;
import weave.beans.LinearRegressionResult;
import weave.beans.RResult;
import weave.config.WeaveContextParams;
import weave.servlets.GenericServlet;
import weave.utils.ListUtils;
import org.rosuda.JRI.Rengine;
import org.rosuda.JRI.RMainLoopCallbacks;
import org.rosuda.JRI.REXP;
import org.rosuda.REngine.REXPMismatchException;

class RCallbacks implements RMainLoopCallbacks
{
	public void rBusy(Rengine arg0, int arg1)
	{
	}

	public String rChooseFile(Rengine arg0, int arg1)
	{
		return null;
	}

	public void rFlushConsole(Rengine arg0)
	{
	}

	public void rLoadHistory(Rengine arg0, String arg1)
	{
	}

	public String rReadConsole(Rengine arg0, String arg1, int arg2)
	{
		return null;
	}

	public void rSaveHistory(Rengine arg0, String arg1)
	{
	}

	public void rShowMessage(Rengine arg0, String arg1)
	{
	}

	public void rWriteConsole(Rengine arg0, String arg1, int arg2)
	{
	}
}

public class RService extends GenericServlet
{
	private static final long serialVersionUID = 1L;

	public RService()
	{
	}

	public void init(ServletConfig config) throws ServletException
	{
		super.init(config);
		docrootPath = WeaveContextParams.getInstance(config.getServletContext()).getDocrootPath();
	}

	private String docrootPath = "";
	private String rFolderName = "R_output";

	// write separate class to start Rserve (TBD)

	private Rengine getRengine()
	{
		Rengine rEngine = null;
		String args[] = { "--save" };
		RCallbacks rCalls = new RCallbacks();
		try
		{
			rEngine = new Rengine(args, true, rCalls);
		}
		catch (Exception e)
		{
			e.printStackTrace();
		}
		return rEngine;
	}

	private String plotEvalScript(Rengine rEngine, String script, boolean showWarnings) throws REXPMismatchException
	{
		String file = String.format("user_script_%s.jpg", UUID.randomUUID());
		String dir = docrootPath + rFolderName + "/";
		(new File(dir)).mkdirs();
		String str = String.format("jpeg(\"%s\")", dir + file);
		evalScript(rEngine, str, showWarnings);
		rEngine.eval(script);
		rEngine.eval("dev.off()");
		return rFolderName + "/" + file;
	}

	private REXP evalScript(Rengine rEngine, String script, boolean showWarnings) throws REXPMismatchException
	{
		// rConnection.voidEval("");
		REXP evalValue;
		if(showWarnings)
			evalValue = rEngine.eval("try({ options(warn=2) \n" + script + "},silent=TRUE)");
		else
			evalValue = rEngine.eval("try({ options(warn=1) \n" + script + "},silent=TRUE)");
		
		//TODO: find REngine equivalent code
//		if (evalValue.inherits("try-error"))
//			throw new RuntimeException(evalValue.asString());
		return evalValue;
	}

	public RResult[] runScript(String[] inputNames, Object[][] inputValues, String[] outputNames, String script, String plotScript, boolean showIntermediateResults, boolean showWarnings) throws RemoteException
	{

		String output = "";
		Rengine rEngine = getRengine();
		RResult[] results = null;
		REXP evalValue;
		try
		{
			// ASSIGNS inputNames to respective Vector in R "like x<-c(1,2,3,4)"
			for (int i = 0; i < inputNames.length; i++)
			{
				String name = inputNames[i];
				if (inputValues[i][0] instanceof String)
				{
					String[] value = ListUtils.copyStringArray(inputValues[i], new String[inputValues[i].length]);
					rEngine.assign(name, value);
				}
				else
				{
					double[] value = ListUtils.copyDoubleArray(inputValues[i], new double[inputValues[i].length]);
					rEngine.assign(name, value);
				}
				// double[] value = inputValues[i];
				System.out.println("input " + name);
				// Assigning Column to its Name in R

			}
			// R Script to EVALUATE inputTA(from R Script Input TextArea)
			if (showIntermediateResults)
			{
				String[] rScript = script.split("\n");
				for (int i = 0; i < rScript.length; i++)
				{
					REXP individualEvalValue = evalScript(rEngine, rScript[i], showWarnings);
					// to-do remove debug information from string
					String trimedString = individualEvalValue.toString();
					while (trimedString.indexOf('[') > 0)
					{
						int pos = trimedString.indexOf('[');
						System.out.println(pos + "\n");
						System.out.println(trimedString + "\n");
						trimedString = trimedString.substring(pos + 1);
					}
					trimedString = "[" + trimedString;
					// String resultString = "Number of Elements:" +
					// individualEvalValue.toDebugString().substring(beginPos
					// ,endPos + 1) +"\n"+
					// individualEvalValue.toDebugString().substring(endPos +
					// 1);
					output = output.concat(trimedString);
					output += "\n";
				}
			}
			else
			{
				REXP completeEvalValue = evalScript(rEngine, script, showWarnings);
				// print debug info
				output = completeEvalValue.toString();
				System.out.println("output: " + output);
			}

			// R Script to EVALUATE outputTA(from R Script Output TextArea)

			if (showIntermediateResults)
			{
				int i;
				int iterationTimes;
				if (plotScript != "")
				{
					results = new RResult[outputNames.length + 2];
					String plotEvalValue = plotEvalScript(rEngine, plotScript, showWarnings);
					results[0] = new RResult("Plot Results", plotEvalValue);
					results[1] = new RResult("Intermediate Results", output);
					i = 2;
					iterationTimes = outputNames.length + 2;
				}
				else
				{
					results = new RResult[outputNames.length + 1];
					results[0] = new RResult("Intermediate Results", output);
					i = 1;
					iterationTimes = outputNames.length + 1;
				}
				// to add intermediate results extra object is created as first
				// input, so results length will be one greater than OutputNames
				// int i =1;
				// int iterationTimes =outputNames.length;
				for (; i < iterationTimes; i++)
				{
					String name;
					// Boolean addedTolist = false;
					if (iterationTimes == outputNames.length + 2)
					{
						name = outputNames[i - 2];
					}
					else
					{
						name = outputNames[i - 1];
					}

					// Script to get R - output
					evalValue = evalScript(rEngine, name, showWarnings);

					int type = evalValue.getType();
					if (type == REXP.XT_ARRAY_STR)
					{
						results[i] = new RResult(name, evalValue.asStringArray());
					}
					else if (type == REXP.XT_ARRAY_INT)
					{
						results[i] = new RResult(name, evalValue.asIntArray());
					}
					else if (type == REXP.XT_ARRAY_DOUBLE)
					{
						double[][] asDoubleMatrix = null;
						try
						{
							asDoubleMatrix = evalValue.asDoubleMatrix();
						}
						catch (Exception e)
						{
						}

						if (asDoubleMatrix != null)
							results[i] = new RResult(name, asDoubleMatrix);
						else
							results[i] = new RResult(name, evalValue.asDoubleArray());
					}
					else
						results[i] = new RResult(name, evalValue.toString());

					System.out.println(name + " = " + evalValue.toString() + "\n");
				}
			}
			else
			{

				int i;
				int iterationTimes;
				if (plotScript != "")
				{
					results = new RResult[outputNames.length + 1];
					String plotEvalValue = plotEvalScript(rEngine, plotScript, showWarnings);
					System.out.println(plotEvalValue);
					results[0] = new RResult("Plot Results", plotEvalValue);
					i = 1;
					iterationTimes = outputNames.length + 1;
				}
				else
				{
					results = new RResult[outputNames.length];
					i = 0;
					iterationTimes = outputNames.length;
				}
				// to outputNames script result
				// results = new RResult[outputNames.length];
				for (; i < iterationTimes; i++)
				{
					String name;
					// Boolean addedTolist = false;
					if (iterationTimes == outputNames.length + 1)
					{
						name = outputNames[i - 1];
					}
					else
					{
						name = outputNames[i];
					}
					// Script to get R - output
					evalValue = evalScript(rEngine, name, showWarnings);
					System.out.println(evalValue);
					int type = evalValue.getType();

					if (type == REXP.XT_ARRAY_STR)
						results[i] = new RResult(name, evalValue.asStringArray());
					else if (type == REXP.XT_ARRAY_INT)
						results[i] = new RResult(name, evalValue.asIntArray());
					else if (type == REXP.XT_ARRAY_DOUBLE)
					{
						double[][] asDoubleMatrix = null;
						try
						{
							asDoubleMatrix = evalValue.asDoubleMatrix();
						}
						catch (Exception e)
						{
						}

						if (asDoubleMatrix != null)
							results[i] = new RResult(name, asDoubleMatrix);
						else
							results[i] = new RResult(name, evalValue.asDoubleArray());
					}
					// if no previous cases were true, return debug string
					else
						results[i] = new RResult(name, evalValue.toString());

					System.out.println(name + " = " + evalValue.toString() + "\n");
				}
			}
		}
		catch (Exception e)
		{
			// e.printStackTrace();
			// to-do remove debug information from string
			output += e.getMessage();
			// to send error from R to As3 side results is created with one
			// object
			results = new RResult[1];
			results[0] = new RResult("Error Statement", output);
		}
		finally
		{
			rEngine.end();
		}
		return results;
	}

	public LinearRegressionResult linearRegression(double[] dataX, double[] dataY) throws RemoteException
	{
		if (dataX.length == 0 || dataY.length == 0)
			throw new RemoteException("Unable to run computation on zero-length arrays.");
		if (dataX.length != dataY.length)
			throw new RemoteException("Unable to run computation on two arrays with different lengths (" + dataX.length
					+ " != " + dataY.length + ").");
		// System.out.println("entering linearRegression()");
		Rengine rEngine = getRengine();
		// System.out.println("got r connection");
		LinearRegressionResult result = new LinearRegressionResult();
		try
		{

			// Push the data to R
			rEngine.assign("x", dataX);
			rEngine.assign("y", dataY);

			// Perform the calculation
			rEngine.eval("fit <- lm(y~x)");

			// option to draw the plot, regression line and store the image

			rEngine.eval(String.format("jpeg(\"%s\")", docrootPath + rFolderName + "/Linear_Regression.jpg"));
			rEngine.eval("plot(x,y)");
			rEngine.eval("abline(fit)");
			rEngine.eval("dev.off()");

			// Get the data from R
			result.setIntercept(rEngine.eval("coefficients(fit)[1]").asDouble());
			result.setSlope(rEngine.eval("coefficients(fit)[2]").asDouble());
			result.setRSquared(rEngine.eval("summary(fit)$r.squared").asDouble());
			result.setSummary("");// rConnection.eval("summary(fit)").asString());
			result.setResidual(rEngine.eval("resid(fit)").asDoubleArray());

		}
		catch (Exception e)
		{
			e.printStackTrace();
			throw new RemoteException(e.getMessage());
		}
		finally
		{
			rEngine.end();
		}
		return result;
	}

	public KMeansClusteringResult kMeansClustering(double[] dataX, double[] dataY, int numberOfClusters, boolean showWarnings) throws RemoteException
	{
		int[] clusterNumber = new int[1];
		clusterNumber[0] = numberOfClusters;
		int[] iterations = new int[1];
		iterations[0] = 2;

		if (dataX.length == 0 || dataY.length == 0)
			throw new RemoteException("Unable to run computation on zero-length arrays.");
		if (dataX.length != dataY.length)
			throw new RemoteException("Unable to run computation on two arrays with different lengths (" + dataX.length
					+ " != " + dataY.length + ").");

		Rengine rEngine = getRengine();
		KMeansClusteringResult kclresult = new KMeansClusteringResult();

		try
		{

			// Push the data to R
			rEngine.assign("x", dataX);
			rEngine.assign("y", dataY);
			rEngine.assign("clusternumber", clusterNumber);
			rEngine.assign("iter.max", iterations);

			// Performing the calculation
			rEngine.eval("dataframe1 <- data.frame(x,y)");
			// Each run of the algorithm gives a different result, thus continue
			// till results are constant
			rEngine
					.eval("Clustering <- function(clusternumber, iter.max)\n{result1 <- kmeans(dataframe1, clusternumber, iter.max)\n result2 <- kmeans(dataframe1, clusternumber, (iter.max-1))\n while(result1$centers != result2$centers){ iter.max <- iter.max + 1 \n result1 <- kmeans(dataframe1, clusternumber, iter.max) \n result2 <- kmeans(dataframe1, clusternumber, (iter.max-1))} \n print(result1) \n print(result2)}");
			rEngine.eval("Cluster <- Clustering(clusternumber, iter.max)");

			// option for drawing a graph, shows centroids

			// Get the data from R
			// Returns a vector indicating which cluster each data point belongs
			// to
			kclresult.setClusterGroup(rEngine.eval("Cluster$cluster").asDoubleArray());
			// Returns the means of each of the clusters
			kclresult.setClusterMeans(rEngine.eval("Cluster$centers").asDoubleMatrix());
			// Returns the size of each cluster
			kclresult.setClusterSize(rEngine.eval("Cluster$size").asDoubleArray());
			// Returns the sum of squares within each cluster
			kclresult.setWithinSumOfSquares(rEngine.eval("Cluster$withinss").asDoubleArray());
			// Returns the image from R
			// option for storing the image of the graphic output from R
			String str = String.format("jpeg(\"%s\")", docrootPath + rFolderName + "/Kmeans_Clustering.jpg");
			System.out.println(str);
			evalScript(rEngine, str, showWarnings);
			rEngine
					.eval("plot(dataframe1,xlab= \"x\", ylab= \"y\", main = \"Kmeans Clustering\", col = Cluster$cluster) \n points(Cluster$centers, col = 1:5, pch = 10)");
			rEngine.eval("dev.off()");
			kclresult.setRImageFilePath("Kmeans_Clustering.jpg");

		}
		catch (Exception e)
		{
			e.printStackTrace();
			throw new RemoteException(e.getMessage());
		}
		finally
		{
			rEngine.end();
		}
		return kclresult;
	}

	public HierarchicalClusteringResult hierarchicalClustering(double[] dataX, double[] dataY) throws RemoteException
	{
		String[] agglomerationMethod = new String[7];
		agglomerationMethod[0] = "ward";
		agglomerationMethod[1] = "average";
		agglomerationMethod[2] = "centroid";
		agglomerationMethod[3] = "single";
		agglomerationMethod[4] = "complete";
		agglomerationMethod[5] = "median";
		agglomerationMethod[6] = "mcquitty";
		String agglomerationMethodType = new String("ward");

		if (dataX.length == 0 || dataY.length == 0)
			throw new RemoteException("Unable to run computation on zero-length arrays.");
		if (dataX.length != dataY.length)
			throw new RemoteException("Unable to run computation on two arrays with different lengths (" + dataX.length
					+ " != " + dataY.length + ").");

		Rengine rEngine = getRengine();
		HierarchicalClusteringResult hclresult = new HierarchicalClusteringResult();
		try
		{

			// Push the data to R
			rEngine.assign("x", dataX);
			rEngine.assign("y", dataY);

			// checking for user method match
			for (int j = 0; j < agglomerationMethod.length; j++)
			{
				if (agglomerationMethod[j].equals(agglomerationMethodType))
				{
					rEngine.assign("method", agglomerationMethod[j]);
				}
			}

			// Performing the calculations
			rEngine.eval("dataframe1 <- data.frame(x,y)");
			rEngine.eval("HCluster <- hclust(d = dist(dataframe1), method)");

			// option for drawing the hierarchical tree and storing the image
			rEngine.eval(String.format("jpeg(\"%s\")", docrootPath + rFolderName + "/Hierarchical_Clustering.jpg"));
			rEngine.eval("plot(HCluster, main = \"Hierarchical Clustering\")");
			rEngine.eval("dev.off()");

			// Get the data from R
			hclresult.setClusterSequence(rEngine.eval("HCluster$merge").asDoubleMatrix());
			hclresult.setClusterMethod(rEngine.eval("HCluster$method").asStringArray());
			// hclresult.setClusterLabels(rConnection.eval("HCluster$labels").asStrings());
			hclresult.setClusterDistanceMeasure(rEngine.eval("HCluster$dist.method").asStringArray());

		}
		catch (Exception e)
		{
			e.printStackTrace();
			throw new RemoteException(e.getMessage());
		}
		finally
		{
			rEngine.end();
		}
		return hclresult;
	}
}
