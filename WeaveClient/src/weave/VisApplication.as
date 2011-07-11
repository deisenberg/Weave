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

package weave
{
	import flash.display.StageDisplayState;
	import flash.events.ContextMenuEvent;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.external.ExternalInterface;
	import flash.geom.Point;
	import flash.net.FileFilter;
	import flash.net.FileReference;
	import flash.net.URLRequest;
	import flash.net.URLVariables;
	import flash.net.navigateToURL;
	import flash.system.System;
	import flash.text.TextField;
	import flash.ui.ContextMenu;
	import flash.ui.ContextMenuItem;
	import flash.utils.getQualifiedClassName;
	
	import mx.binding.utils.BindingUtils;
	import mx.containers.VDividedBox;
	import mx.controls.Alert;
	import mx.controls.Label;
	import mx.controls.ProgressBar;
	import mx.controls.ProgressBarLabelPlacement;
	import mx.controls.TabBar;
	import mx.controls.Text;
	import mx.controls.TextArea;
	import mx.core.Application;
	import mx.core.UIComponent;
	import mx.events.ChildExistenceChangedEvent;
	import mx.events.FlexEvent;
	import mx.managers.PopUpManager;
	import mx.rpc.AsyncToken;
	import mx.rpc.events.FaultEvent;
	import mx.rpc.events.ResultEvent;
	
	import weave.KeySetContextMenuItems;
	import weave.Reports.WeaveReport;
	import weave.SearchEngineUtils;
	import weave.api.WeaveAPI;
	import weave.api.core.ILinkableObject;
	import weave.api.data.IAttributeColumn;
	import weave.api.data.IDataSource;
	import weave.api.data.IProgressIndicator;
	import weave.api.data.IQualifiedKey;
	import weave.api.getCallbackCollection;
	import weave.api.getSessionState;
	import weave.api.services.IURLRequestUtils;
	import weave.compiler.BooleanLib;
	import weave.compiler.MathLib;
	import weave.core.DynamicState;
	import weave.core.ErrorManager;
	import weave.core.LinkableBoolean;
	import weave.core.StageUtils;
	import weave.core.WeaveJavaScriptAPI;
	import weave.core.weave_internal;
	import weave.data.AttributeColumns.ColorColumn;
	import weave.data.AttributeColumns.FilteredColumn;
	import weave.data.AttributeColumns.KeyColumn;
	import weave.data.KeySets.KeyFilter;
	import weave.data.KeySets.KeySet;
	import weave.primitives.AttributeHierarchy;
	import weave.services.DelayedAsyncResponder;
	import weave.services.LocalAsyncService;
	import weave.services.ProgressIndicator;
	import weave.ui.AlertTextBox;
	import weave.ui.AlertTextBoxEvent;
	import weave.ui.AttributeSelectorPanel;
	import weave.ui.AutoResizingTextArea;
	import weave.ui.ColorBinEditor;
	import weave.ui.CustomContextMenuManager;
	import weave.ui.DatasetLoader;
	import weave.ui.DraggablePanel;
	import weave.ui.EquationEditor;
	import weave.ui.ErrorLogPanel;
	import weave.ui.ExportSessionStatePanel;
	import weave.ui.NewUserWizard;
	import weave.ui.OICLogoPane;
	import weave.ui.PrintFormat;
	import weave.ui.ProbeToolTipEditor;
	import weave.ui.RTextEditor;
	import weave.ui.SelectionManager;
	import weave.ui.SessionStateEditor;
	import weave.ui.SessionStatesDisplay;
	import weave.ui.SubsetManager;
	import weave.ui.WizardPanel;
	import weave.ui.annotation.SessionedTextBox;
	import weave.ui.controlBars.VisTaskbar;
	import weave.ui.controlBars.WeaveMenuBar;
	import weave.ui.controlBars.WeaveMenuItem;
	import weave.ui.editors.AddDataSourceComponent;
	import weave.ui.editors.EditDataSourceComponent;
	import weave.ui.settings.GlobalUISettings;
	import weave.utils.BitmapUtils;
	import weave.utils.CSSUtils;
	import weave.utils.DebugUtils;
	import weave.utils.DrawUtils;
	import weave.utils.NumberUtils;
	import weave.visualization.tools.ColorBinLegendTool;
	import weave.visualization.tools.CompoundBarChartTool;
	import weave.visualization.tools.DataTableTool;
	import weave.visualization.tools.DimensionSliderTool;
	import weave.visualization.tools.GaugeTool;
	import weave.visualization.tools.HistogramTool;
	import weave.visualization.tools.LineChartTool;
	import weave.visualization.tools.MapTool;
	import weave.visualization.tools.PieChartHistogramTool;
	import weave.visualization.tools.PieChartTool;
	import weave.visualization.tools.RadViz2Tool;
	import weave.visualization.tools.RadVizTool;
	import weave.visualization.tools.RamachandranPlotTool;
	import weave.visualization.tools.SP2;
	import weave.visualization.tools.ScatterPlotTool;
	import weave.visualization.tools.StickFigureGlyphTool;
	import weave.visualization.tools.ThermometerTool;
	import weave.visualization.tools.TimeSliderTool;
	import weave.visualization.tools.WeaveWordleTool;

	use namespace weave_internal;

	
	/**	VisApplication
   	 *  @author abaumann
 	 * 	A class that extends Application to provide a workspace to add tools, handle setting of settings from files, etc.
 	 **/
	public class VisApplication extends Application implements ILinkableObject
	{
		MXClasses; // Referencing this allows all Flex classes to be dynamically created at runtime.


		{ /** BEGIN STATIC CODE BLOCK **/ 
			Weave.initialize(); // referencing this here causes all WeaveAPI implementations to be registered.
		} /** END STATIC CODE BLOCK **/ 
		
		
		// Optional menu bar (top of the screen) and task bar (bottom of the screen).  These would be used for an advanced analyst
		// view to add new tools, manage windows, do advanced tasks, etc.
		private var _weaveMenu:WeaveMenuBar = null;
		private var _visTaskbar:VisTaskbar = null;
		
		
		// The XML file that defines the default layout of the page if no parameter is passed that specifies another file to use
		private var _defaultsXML:XML = null;
		
		// The array of data tables that are used in this application, one or more data tables are needed to visualize some data
		private var _dataTableNames:Array = [];
		
		// This will be used to incorporate branding into any weave view.  Linkable to the Open Indicators Consortium website.
		private var _oicLogoPane:OICLogoPane = new OICLogoPane();

		//this sprite will be used to draw curved lines to show connections between two UIComponents
		//private var _connectionsLayer:Sprite = new Sprite();
		
		/**
		 * static methods
		 */
		
		// global VisApplication instance
		private static var _thisInstance:VisApplication = null;
		public static function get instance():VisApplication
		{
			return _thisInstance;
		}

		public function VisApplication()
		{
			super();
			this.setStyle('backgroundColor',0xCCCCCC);
			this.pageTitle = "Open Indicators Weave";

			_visTaskbar = new VisTaskbar();
			visDesktop = new VisDesktop();
			
			// resize to parent size each frame because percentWidth,percentHeight doesn't seem reliable when application is nested
			addEventListener(Event.ENTER_FRAME, function(..._):*{
				if (!parent)
					return;
				
				width = parent.width;
				height = parent.height;
			}, true);
			
//			this.frameRate = 60;
			
			ErrorManager.callbacks.addGroupedCallback(this, ErrorLogPanel.openErrorLog);
			
			Weave.root.childListCallbacks.addImmediateCallback(this, handleWeaveListChange);
			
			_thisInstance = this;
			
			setStyle("paddingLeft", 0);
			setStyle("paddingRight", 0);
			setStyle("paddingTop", 0);
			setStyle("paddingBottom", 0);
			
			setStyle("marginLeft", 0);
			setStyle("marginRight", 0);
			setStyle("marginTop", 0);
			setStyle("marginBottom", 0);
			
			setStyle("verticalGap", 0);
			setStyle("horizingalGap", 0);

			// default has menubar and taskbar unless specified otherwise in defaults file
			Weave.properties.enableMenuBar.addGroupedCallback(this, toggleMenuBar);
			Weave.properties.enableTaskbar.addGroupedCallback(this, toggleTaskBar, true);
			
			Weave.properties.pageTitle.addGroupedCallback(this, updatePageTitle);
			
			
			
			this.autoLayout = true;
			
			// no scrolling -- need to make "workspaces" you can switch between
			this.horizontalScrollPolicy = "off";
			this.verticalScrollPolicy   = "off";
			
			visDesktop.verticalScrollPolicy   = "off";
			visDesktop.horizontalScrollPolicy = "off";
			
			getCallbackCollection(Weave.root.getObject(Weave.SAVED_SELECTION_KEYSETS)).addGroupedCallback(this, setupSelectionsMenu);
			getCallbackCollection(Weave.root.getObject(Weave.SAVED_SUBSETS_KEYFILTERS)).addGroupedCallback(this, setupSubsetsMenu);

			//add event listerner on closing window to send a message to the sender LocalConnection close the connection
			//addEventListener(Event.CLOSE,handleClosingEvent);
			getURLParams();
			if (getConnectionName() != null)
			{
				// disable interface until connected to admin console
				var _this:VisApplication = this;
				_this.enabled = false;
				var errorHandler:Function = function(..._):void
				{
					Alert.show("Unable to connect to the Admin Console.\nYou will not be able to save your session state to the server.", "Connection error");
					_this.enabled = true;
				};
				var pendingAdminService:LocalAsyncService = new LocalAsyncService(this, false, getConnectionName());
				pendingAdminService.errorCallbacks.addGroupedCallback(this, errorHandler);
				// when admin console responds, set adminService
				DelayedAsyncResponder.addResponder(
						pendingAdminService.invokeAsyncMethod("ping"),
						function(..._):*
						{
							//Alert.show("Connected to Admin Console");
							_this.enabled = true;
							adminService = pendingAdminService;
							toggleMenuBar();
							StageUtils.callLater(this,setupVisMenuItems,null,false);
						},
						errorHandler
					);
			}
			
			getCallbackCollection(Weave.properties).addGroupedCallback(this, setupVisMenuItems);
			
			Weave.properties.enableExportToolImage.addGroupedCallback(this, setupContextMenu);
			Weave.properties.dataInfoURL.addGroupedCallback(this, setupContextMenu);
			Weave.properties.enableSubsetControls.addGroupedCallback(this, setupContextMenu);
			Weave.properties.enableRightClick.addGroupedCallback(this, setupContextMenu);
			Weave.properties.enableAddDataSource.addGroupedCallback(this, setupContextMenu);
			Weave.properties.enableEditDataSource.addGroupedCallback(this, setupContextMenu);
			Weave.properties.backgroundColor.addGroupedCallback(this, handleBackgroundColorChange);
//			Weave.properties.showViewBar.addGroupedCallback(this, addViewBar);
		}
		
		private function handleBackgroundColorChange():void
		{
			VisApplication.instance.setStyle("backgroundColor",Weave.properties.backgroundColor.value);
		}
		
		// This VBox holds the optional menu bar, visDesktop, and optional task bar (stacked vertically)
		//private var _applicationVBox:VBox = new VBox();
		// The desktop is the entire viewable area minus the space for the optional menu bar and taskbar
		public var visDesktop:VisDesktop = null;
		
		//get parameters from URL. Used for setting connectionName for LocalConnection
		private var _urlParams:Object;
		private function getConnectionName():String
		{
			return _urlParams['connectionName'] as String;
		}
		
		private function getClientConfigFileName():String
		{
			if (_urlParams['defaults'] == undefined)
				return null;
			
			return unescape(_urlParams['defaults'] as String);
		}
		
		/**
		 * @return true or false, depending what the 'editable' URL parameter is set to.
		 */
		private function getEditableSettingFromURL():Boolean
		{
			return BooleanLib.toBoolean(_urlParams['editable'] as String);
		}
				
		private function getURLParams():void
		{
			//var address:String;
			var queryString:String;
			_urlParams = {};

			try
			{
				//address = ExternalInterface.call("window.location.href.toString");
				queryString = ExternalInterface.call("window.location.search.substring", 1); // get text after "?"
				_urlParams = new URLVariables(queryString);
			}
			catch(e:Error)
			{
				trace(e.getStackTrace());
			}
		}

		private function get _applicationVBox():Application { return application as Application; }
		
//		[Embed("/weave/resources/images/panelButtonEnlarged.png")]
//		public var panelButton:Class;
//		[Embed("/weave/resources/images/panelButtonRed.png")]
//		public var panelButtonRed:Class;
//		[Embed("/weave/resources/images/panelButtonBlue.png")]
//		public var panelButtonBlue:Class;
//		private var buttonHBox:HBox= new HBox();
//		private var _userPreferencesIcon:Button = new Button();
//		private var _viewStack:ViewStack = new ViewStack();
//		private var _viewTabBar:ViewBar = new ViewBar();
//		private var _addTab:HBox = new HBox();

//		private function addViewBar():void
//		{
//			_userPreferencesIcon.emphasized=true;
//			_userPreferencesIcon.setStyle("skin", panelButton);
//			_userPreferencesIcon.setStyle("overSkin", panelButtonBlue);
//			_userPreferencesIcon.setStyle("paddingLeft", 1);
//			_userPreferencesIcon.buttonMode=true;
//			_userPreferencesIcon.move(5,0);
//			_userPreferencesIcon.width=25;
//			_userPreferencesIcon.height=23;
//			_userPreferencesIcon.toolTip="Click to open the User Preferences Panel";
//			_userPreferencesIcon.addEventListener(MouseEvent.CLICK, handleUserPreferencesIconClicked);
//
//			_viewTabBar.dataProvider=_viewStack;
//			_viewTabBar.setStyle("horizontalGap", 2);
//			_viewTabBar.setStyle("paddingTop", 5);
//			_viewTabBar.setStyle("fontFamily", WeaveProperties.DEFAULT_FONT_FAMILY );
//			_viewTabBar.setStyle("fontWeight", "bold");
//			_viewTabBar.rotation = -90;
//			_viewTabBar.move(0,this.height);
//			_viewTabBar.height=30;
//			_viewTabBar.width=this.height - _userPreferencesIcon.height;
//			
//			addChild(_userPreferencesIcon);
//			addChild(_viewTabBar);
//			_viewTabBar.visible = _userPreferencesIcon.visible = Weave.properties.showViewBar.value ;
//			_viewStack.x = (Weave.properties.showViewBar.value) ? 30 : 0 ;
//			
//		}

		private var _maxProgressBarValue:int = 0;
		private var _progressBar:ProgressBar = new ProgressBar;
		private function handleProgressIndicatorCounterChange():void
		{
			var pendingCount:int = WeaveAPI.ProgressIndicator.getTaskCount();
			var tempString:String = pendingCount + " Pending Request" + (pendingCount == 1 ? '' : 's');
			
			_progressBar.label = tempString;

			if (pendingCount == 0)				// hide progress bar and text area
			{
				_progressBar.visible = false;
				_progressBar.setProgress(0, 1); // reset progress bar
				
				_maxProgressBarValue = 0;
			}
			else								// display progress bar and text area
			{
				if (visDesktop.visible == false)
					return;
				
				_progressBar.alpha = .8;
				
				if (pendingCount > _maxProgressBarValue)
					_maxProgressBarValue = pendingCount;
				
				_progressBar.setProgress(WeaveAPI.ProgressIndicator.getNormalizedProgress(), 1); // progress between 0 and 1
				_progressBar.visible = true;
			}
			
		}
		
		private var _selectionIndicatorText:Text = new Text;
		private static var selection:KeySet = Weave.root.getObject(Weave.DEFAULT_SELECTION_KEYSET) as KeySet;
		// ToDo How to get the total number of records?
		private function handleSelectionIndicatorCounterChange():void
		{
			if (selection.keys.length == 0)
				_selectionIndicatorText.visible = false;
			else
			{
				_selectionIndicatorText.visible = true;
				_selectionIndicatorText.text = selection.keys.length.toString() + " Records Selected";
			}
		}
		
		override protected function createChildren():void
		{
			super.createChildren();
			/*var mapc:MapComponent = new MapComponent();
			mapc.initialize();
			mapc.validateNow();
			mapc.extent = new MapExtent(90, -90, 180, -180);
			mapc.provider = "OPEN_STREET_MAP";
			mapc.enabled = true;
			mapc.visible = true;
			mapc.percentHeight = 100;
			mapc.percentWidth = 50;
			mapc.alpha = 1;
			visDesktop.addChild(mapc);			
			*/
			
			_applicationVBox.addChild(visDesktop);
			visDesktop.percentWidth = 100;
			visDesktop.percentHeight = 100;

//			_applicationVBox.label="Admin View";
//			_applicationVBox.percentWidth = 100;
//			_applicationVBox.percentHeight = 100;
//			_applicationVBox.setStyle("verticalGap", 1);
//			_applicationVBox.setStyle("cornerRadius", 0);
//			addChild(_viewStack);
//			
//			_applicationHBox.percentWidth = 100;
//			_applicationHBox.percentHeight = 100;
//			_applicationHBox.setStyle("verticalGap", 0);
//			_applicationHBox.setStyle("cornerRadius", 0);
//			
//			_viewStack.percentHeight=100;
//			_viewStack.percentWidth=100;
//			
//			_addTab.label="+";
//			_viewStack.addChild(_addTab);
//			_applicationVBox.addChild(_applicationHBox);
//			_applicationHBox.addChild(visDesktop);
//			_viewStack.addChild(_applicationVBox);
//			
//			_viewStack.selectedChild=_applicationVBox;
//			addViewBar();
//			_viewTabBar.addEventListener(ItemClickEvent.ITEM_CLICK, handleTabSelected);
//			addEventListener(ResizeEvent.RESIZE,handleTabBarResize);
			
			// Code for selection indicator
			getCallbackCollection(selection).addGroupedCallback(this, handleSelectionIndicatorCounterChange, true);
			visDesktop.addChild(_selectionIndicatorText);
			_selectionIndicatorText.visible = false;
			_selectionIndicatorText.setStyle("color", 0xFFFFFF);
			_selectionIndicatorText.opaqueBackground = 0x000000;
			_selectionIndicatorText.setStyle("bottom", 0);
			_selectionIndicatorText.setStyle("right", 0);
			
			getCallbackCollection(WeaveAPI.ProgressIndicator).addGroupedCallback(this, handleProgressIndicatorCounterChange, true);
			visDesktop.addChild(_progressBar);
			_progressBar.visible = false;
			_progressBar.x = 0;
			_progressBar.setStyle("bottom", 0);
			_progressBar.setStyle("trackHeight", 16); //TODO: global UI setting instead of 12?
			_progressBar.setStyle("borderColor", 0x000000);
			_progressBar.setStyle("color", 0xFFFFFF); //color of text
			_progressBar.setStyle("barColor", "haloBlue");
			_progressBar.setStyle("trackColors", [0x000000, 0x000000]);
			_progressBar.labelPlacement = ProgressBarLabelPlacement.CENTER;
			_progressBar.label = '';
			_progressBar.mode = "manual"; 
			_progressBar.minHeight = 16;
			_progressBar.minWidth = 135; // constant

			
			
			/*visDesktop.width =  this.width;
			visDesktop.height = this.height;*/
			
//			Weave.properties.fontFamily.value = getStyle("fontFamily");
//			Weave.properties.fontSize.value = getStyle("fontSize"); //default fontSize 10
			Weave.properties.backgroundColor.value = getStyle("backgroundColor");
			
			visDesktop.addEventListener(ChildExistenceChangedEvent.CHILD_REMOVE, function(e:Event):void { setupWindowMenu() } );
			
/*			
			var prevTab:int = 0;
			var bar:TabBar = new TabBar();
			var states:Array = [null,null,null];
			bar.dataProvider = ['a','b','c'];
			bar.percentWidth = 100;
			var tabChange:Function = function(newTab:int):void{
				states[prevTab] = Weave.root.getSessionState();
				Weave.root.setSessionState(states[newTab] ? states[newTab] : states[prevTab], true);
				prevTab = newTab;
			};
			BindingUtils.bindSetter(tabChange, bar, 'selectedIndex');
			addChildAt(bar, 0);
//*/			
			
			//drawConnection();
			loadPage();
		}
		
//		private function handleTabBarResize(event:ResizeEvent):void
//		{
//			_viewTabBar.move(0,this.height);
//			_viewTabBar.width=this.height - _userPreferencesIcon.height;
//		}
//		private function handleTabSelected(event:ItemClickEvent):void
//		{
//			var _newChild:HBox = new HBox();
//			if (event.label == "+") _viewStack.addChild(_newChild);
//			_newChild.label="View "+(_viewStack.numChildren-1);
//			_viewTabBar.width=this.height - _userPreferencesIcon.height;
//		}
//		private function handleUserPreferencesIconClicked(event:MouseEvent):void
//		{
//			openGlobalUIPreferencesPanel();
//		}
//		private var _adminMode:Boolean = false;
//		public function get adminMode():Boolean
//		{
//			return _adminMode;
//		}
//		public function set adminMode(value:Boolean):void
//		{
//			//disable admin features:
//			_adminMode = value;
//		}

		private var adminService:LocalAsyncService = null;
		
		
		private var sessionStates:Array = new Array();	//Where the session states are stored.
		private var sessionCount:int = 0;
		private var sessionTotal:int = 0;				//For naming purposes.
		
		private function saveAction():void{
			
			var dynObject:DynamicState = new DynamicState();
			
			sessionTotal++;
			sessionCount = sessionStates.length;
			dynObject.sessionState = getSessionState(Weave.root);
			dynObject.objectName = "Weave Session State " + ( sessionTotal + 1 );
			sessionStates[sessionCount] = dynObject;
			
		}
		
		private function copySessionStateToClipboard():void
		{
			System.setClipboard(Weave.getSessionStateXML().toXMLString());
		}
		
		private function saveSessionStateToServer():void
		{
			var fileSaveDialogBox:AlertTextBox;
			fileSaveDialogBox = PopUpManager.createPopUp(this,AlertTextBox) as AlertTextBox;
			fileSaveDialogBox.textInput = getClientConfigFileName();
			fileSaveDialogBox.title = "Save File";
			fileSaveDialogBox.message = "Save current Session State to server?";
			fileSaveDialogBox.addEventListener(AlertTextBoxEvent.BUTTON_CLICKED, handleFileSaveClose);
			PopUpManager.centerPopUp(fileSaveDialogBox);
			//fileSaveDialogBox.fileNameTextBox.text = getClientConfigFileName();
			//fileSaveDialogBox.yes = handleOverwriteAlert;
		}
		
		private function handleFileSaveClose(event:AlertTextBoxEvent):void
		{
			if (event.confirm)
				savePreviewSessionState(event.textInput);
		}
		
		private function savePreviewSessionState(fileName:String):void
		{
			if (adminService == null)
			{
				Alert.show("Not connected to Admin Console.\nSession State was not saved.", "Error");
				return;
			}
			
			// temporarily disable sessioning so config saved to server has sessioning disabled.
			_disableSetupVisMenuItems = true; // stop the session settings from changing the vis menu
			Weave.properties.enableSessionMenu.value = false;
			Weave.properties.enableSessionEdit.value = false;
			
			//var clientConfigFileName:String = getClientConfigFileName();
			var token:AsyncToken = adminService.invokeAsyncMethod(
					'saveWeaveFile',
					[Weave.getSessionStateXML().toXMLString(), fileName, true]
				);
			token.addResponder(new DelayedAsyncResponder(
					function(event:ResultEvent, token:Object = null):void
					{
						Alert.show(String(event.result), "Admin Console Response");
					},
					function(event:FaultEvent, token:Object = null):void
					{
						Alert.show(event.fault.message, event.fault.name);
					},
					null
				));
			
			Weave.properties.enableSessionMenu.value = true;
			Weave.properties.enableSessionEdit.value = true;
			_disableSetupVisMenuItems = false;
			setupVisMenuItems();
		}
		
		// this function may be called by the Admin Console to close this window
		public function closeWeavePopup():void
		{
			ExternalInterface.call("window.close()");
		}

		public static var showBorders:Boolean ;
		private function toggleMenuBar():void
		{
			if (Weave.properties.enableMenuBar.value || adminService || getEditableSettingFromURL())
			{
				DraggablePanel.showRollOverBorders = true;
				if (!_weaveMenu)
				{
					_weaveMenu = new WeaveMenuBar();

					//trace("MENU BAR ADDED");
					_weaveMenu.percentWidth = 100;
					StageUtils.callLater(this,setupVisMenuItems,null,false);
					
					_applicationVBox.addChildAt(_weaveMenu, 0);
					
					//if (visDesktop.contains(_oicLogoPane))
					//	visDesktop.removeChild(_oicLogoPane);
					if (_applicationVBox.contains(_oicLogoPane))
						_applicationVBox.removeChild(_oicLogoPane);
				}
				
				// always show menu bar when admin service is present
				_weaveMenu.alpha = Weave.properties.enableMenuBar.value ? 1.0 : 0.3;
			}
			// otherwise there is no menu bar, (which normally includes the oiclogopane, so add one to replace it)
			else
			{
				DraggablePanel.showRollOverBorders = false;
				try
				{
		   			if (_weaveMenu && _applicationVBox.contains(_weaveMenu))
						_applicationVBox.removeChild(_weaveMenu);

		   			_weaveMenu = null;
					
					// TODO: the OIC logo pane needs to be better worked out -- it cannot interfere with tool functionality or be in the way...
					//_oicLogoPane.setStyle("right", 0);
					//_oicLogoPane.setStyle("top", 0);
					//addChildAt(_oicLogoPane, this.numChildren);
					_applicationVBox.addChildAt(_oicLogoPane, _applicationVBox.numChildren);
					_applicationVBox.setStyle("horizontalAlign", "right");
				}
				catch(error:Error)
				{
					trace(error.getStackTrace());
				}
			}
		}
		
		private var _dataMenu:WeaveMenuItem  = null;
		private var _exportMenu:WeaveMenuItem  = null;
		private var _sessionMenu:WeaveMenuItem = null;
		private var _toolsMenu:WeaveMenuItem   = null;
		private var _windowMenu:WeaveMenuItem  = null;
		private var _selectionsMenu:WeaveMenuItem = null;
		private var _subsetsMenu:WeaveMenuItem = null;
		private var _aboutMenu:WeaveMenuItem   = null;

		private var _disableSetupVisMenuItems:Boolean = false; // this flag disables the setupVisMenuItems() function temporarily while true
		
		private function setupVisMenuItems():void
		{
			if (_disableSetupVisMenuItems)
				return;
			
			if (!_weaveMenu)
				return;
			
			_weaveMenu.validateNow();
			
			//TEMPORARY SOLUTION -- enable sessioning if loaded through admin console
			if (!Weave.properties.enableSessionMenu.value || !Weave.properties.enableSessionEdit.value)
			{
				if (adminService != null)
				{
					Weave.properties.enableSessionMenu.value = true;
					Weave.properties.enableSessionEdit.value = true;
				}
			}
			
			_weaveMenu.removeAllMenus();
			
			if (Weave.properties.enableDataMenu.value)
			{
				_dataMenu = _weaveMenu.addMenuToMenuBar("Data", false);
				_weaveMenu.addMenuItemToMenu(_dataMenu,
					new WeaveMenuItem("Refresh all data source hierarchies",
						function ():void {
							var sources:Array = Weave.root.getObjects(IDataSource);
							for each (var source:IDataSource in sources)
								(source.attributeHierarchy as AttributeHierarchy).value = null;
						},
						null,
						function():Boolean { return Weave.properties.enableRefreshHierarchies.value }
					)
				);
//				_weaveMenu.addMenuItemToMenu(_dataMenu,
//					new WeaveMenuItem(
//						"Import new dataset ...",
//						function ():void {
//							var loader:DatasetLoader = createGlobalObject(DatasetLoader) as DatasetLoader;
//							loader.browseForFiles();
//						},
//						null,
//						function():Boolean { return Weave.properties.enableNewDataset.value; }
//					)
//				);
				if(Weave.properties.enableAddDataSource.value)
					_weaveMenu.addMenuItemToMenu(_dataMenu,new WeaveMenuItem("Add New Datasource",AddDataSourceComponent.showAsPopup));
				
				if(Weave.properties.enableEditDataSource.value)
					_weaveMenu.addMenuItemToMenu(_dataMenu,new WeaveMenuItem("Edit Datasources",EditDataSourceComponent.showAsPopup));
				
					

				/*
				if (Weave.properties.enableAddWeaveDataSource.value)
					_weaveMenu.addMenuItemToMenu(_importMenu, new WeaveMenuItem("Add WeaveDataSource", null, createGlobalObject, [WeaveDataSource, "WeaveDataSource"], false));
				if (Weave.properties.enableAddGrailsDataSource.value)
        	  		_weaveMenu.addMenuItemToMenu(_importMenu, new WeaveMenuItem("Add GrailsDataSource", null, createGlobalObject, [GrailsDataSource, "GrailsDataSource"], false));
				*/
			}
			
			
			if (Weave.properties.enableExportToolImage.value)
			{
				_exportMenu = _weaveMenu.addMenuToMenuBar("Export", false);
				if (Weave.properties.enableExportApplicationScreenshot.value)
					_weaveMenu.addMenuItemToMenu(_exportMenu, new WeaveMenuItem("Save or Print Application Screenshot...", printOrExportImage, [this]));
//				_visMenu.addMenuItemToMenu(_exportMenu, new VisMenuItem("Data Table...", null, createGlobalObject, [DataTableTool]));
			}
			
			if (Weave.properties.enableDynamicTools.value)
			{
				_toolsMenu = _weaveMenu.addMenuToMenuBar("Tools", false);
				//_visMenu.addMenuItemToMenu(_toolsMenu, new VisMenuItem("Equation Editor", null, createGlobalObject, [EquationEditor]));

				createToolMenuItem(Weave.properties.showColorController, "Show Color Controller", ColorBinEditor.openDefaultEditor);
				createToolMenuItem(Weave.properties.showProbeToolTipEditor, "Show Probe ToolTip Editor", ProbeToolTipEditor.openDefaultEditor );
				createToolMenuItem(Weave.properties.showEquationEditor, "Show Equation Editor", createGlobalObject, [EquationEditor, "EquationEditor"]);
				createToolMenuItem(Weave.properties.showAttributeSelector, "Show Attribute Selector", AttributeSelectorPanel.openDefaultSelector);
				
				_weaveMenu.addSeparatorToMenu(_toolsMenu);
				
				createToolMenuItem(Weave.properties.enableAddBarChart, "Add Bar Chart", createGlobalObject, [CompoundBarChartTool]);
				createToolMenuItem(Weave.properties.enableAddColormapHistogram, "Add Color Histogram", createColorHistogram);
				createToolMenuItem(Weave.properties.enableAddColorLegend, "Add Color Legend", createGlobalObject, [ColorBinLegendTool]);
				createToolMenuItem(Weave.properties.enableAddDataTable, "Add Data Table", createGlobalObject, [DataTableTool]);
				createToolMenuItem(Weave.properties.enableAddDimensionSliderTool, "Add Dimension Slider Tool", createGlobalObject, [DimensionSliderTool]);
				createToolMenuItem(Weave.properties.enableAddGaugeTool, "Add Gauge Tool", createGlobalObject, [GaugeTool]);
				createToolMenuItem(Weave.properties.enableAddHistogram, "Add Histogram", createGlobalObject, [HistogramTool]);
				createToolMenuItem(Weave.properties.enableAddLineChart, "Add Line Chart", createGlobalObject, [LineChartTool]);
				createToolMenuItem(Weave.properties.enableAddMap, "Add Map", createGlobalObject, [MapTool]);
				createToolMenuItem(Weave.properties.enableAddPieChart, "Add Pie Chart", createGlobalObject, [PieChartTool]);
				createToolMenuItem(Weave.properties.enableAddPieChartHistogram, "Add Pie Chart Histogram", createGlobalObject, [PieChartHistogramTool]);
				createToolMenuItem(Weave.properties.enableAddRScriptEditor, "Add R Script Editor", createGlobalObject, [RTextEditor]);
				createToolMenuItem(Weave.properties.enableAddScatterplot, "Add Scatterplot", createGlobalObject, [ScatterPlotTool]);
				createToolMenuItem(Weave.properties.enableAddThermometerTool, "Add Thermometer Tool", createGlobalObject, [ThermometerTool]);
				createToolMenuItem(Weave.properties.enableAddTimeSliderTool, "Add Time Slider Tool", createGlobalObject, [TimeSliderTool]);	

//				_weaveMenu.addSeparatorToMenu(_toolsMenu);
//				
//				createToolMenuItem(Weave.properties.enableAddRadViz, "Add RadViz", createGlobalObject, [RadVizTool]);
//				createToolMenuItem(Weave.properties.enableAddRadViz2, "Add RadViz2", createGlobalObject, [RadViz2Tool]);
//				createToolMenuItem(Weave.properties.enableAddWordle, "Add Wordle", createGlobalObject, [WeaveWordleTool]);
//				createToolMenuItem(Weave.properties.enableAddStickFigurePlot, "Add Stick Figure Plot", createGlobalObject, [StickFigureGlyphTool]);
//				createToolMenuItem(Weave.properties.enableAddRamachandranPlot, "Add RamachandranPlot", createGlobalObject, [RamachandranPlotTool]);
//				createToolMenuItem(Weave.properties.enableAddSP2, "Add SP2", createGlobalObject, [SP2]);
				
				_weaveMenu.addSeparatorToMenu(_toolsMenu);
				
				createToolMenuItem(Weave.properties.enableNewUserWizard, "New User Wizard", function():void {
					var userUI:NewUserWizard = new NewUserWizard();
					WizardPanel.createWizard(instance,userUI);
				});
			}
			
			if (Weave.properties.enableSelectionsMenu.value)
			{	
				_selectionsMenu = _weaveMenu.addMenuToMenuBar("Selections", true);
				setupSelectionsMenu();
			}
			
			if (Weave.properties.enableSubsetsMenu.value)
			{	
				_subsetsMenu = _weaveMenu.addMenuToMenuBar("Subsets", true);
				setupSubsetsMenu();
			}
			
			
			if (Weave.properties.enableSessionMenu.value)
			{
				_sessionMenu = _weaveMenu.addMenuToMenuBar("Session", false);
				if (Weave.properties.enableSessionBookmarks.value)
				{
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("Create session state save point", saveAction));
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("Show saved session states", SessionStatesDisplay.openDefaultEditor, [sessionStates]));
				}
				
				_weaveMenu.addSeparatorToMenu(_sessionMenu);
				
				if (Weave.properties.enableSessionEdit.value)
				{
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("Edit session state", SessionStateEditor.openDefaultEditor));
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("Copy session state to clipboard", copySessionStateToClipboard));
				}
				
				_weaveMenu.addSeparatorToMenu(_sessionMenu);
				
				if (Weave.properties.enableSessionImport.value)
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("Import session state ...", handleImportSessionState, null, true));
				if (Weave.properties.enableSessionExport.value)
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("Export session state...", handleExportSessionState));

				_weaveMenu.addSeparatorToMenu(_sessionMenu);

				if (adminService)
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("Save session state to server", saveSessionStateToServer));
				
				_weaveMenu.addSeparatorToMenu(_sessionMenu);
				
				if (Weave.properties.enableUserPreferences.value)
					_weaveMenu.addMenuItemToMenu(_sessionMenu, new WeaveMenuItem("User interface preferences", GlobalUISettings.openGlobalEditor));
			}
			
			if (Weave.properties.enableWindowMenu.value)
			{	
				_windowMenu = _weaveMenu.addMenuToMenuBar("Window", true);
				setupWindowMenu();
			}
			
			if (Weave.properties.enableAboutMenu.value)
			{
				_aboutMenu = _weaveMenu.addMenuToMenuBar("About", false);
				//_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem("Help", function():void { HelpPanel.showAsPopup(); }));
				
				//_weaveMenu.addSeparatorToMenu(_aboutMenu);
				
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem("Weave Version: " + Weave.properties.version.value));
				
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem("Visit http://www.openindicators.org", function ():void {
					navigateToURL(new URLRequest("http://www.openindicators.org"), "_blank");
				}));
				
				
				
				/*// name of XML defaults file:
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem("Session State Used:"), true );
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem("", function():String {
																					if (_defaultsFilename == null) 
																						return "\tNo file selected."; 
																					return "\t"+_defaultsFilename} ) );
				
				// name of each data source used:
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem("Data Source(s) Used:"), true );
				_weaveMenu.addMenuItemToMenu(_aboutMenu, new WeaveMenuItem("", function ():String {
					if (Weave.getNames(IDataSource).length == 0)
						return "\tNo data sources specified.";
					return "\t"+Weave.getNames(IDataSource).toString();
				} ) );*/
				// name of each shape layer used:
				/*_visMenu.addMenuItemToMenu(_aboutMenu, new VisMenuItem("Shape Data Used in Maps:"), true );
				_visMenu.addMenuItemToMenu(_aboutMenu, new VisMenuItem("", function ():String {
						var shapeNames:Array = [];
						for (var i:int = 0; i < visDesktop.numChildren; i++)
						{
							var mapTool:MapTool = visDesktop.getChildAt(i) as MapTool;
							
							//if (mapTool)
							//	shapeNames.push(mapTool.
						}
						
						return null; 
					}
				
				) );*/
			}
		}
		
		private function createToolMenuItem(toggle:LinkableBoolean, title:String, callback:Function, params:Array = null):void
		{
			if (toggle.value)
				_weaveMenu.addMenuItemToMenu(_toolsMenu, new WeaveMenuItem(title, callback, params));
		}
		
		private function toggleTaskBar():void
		{
			if (Weave.properties.enableTaskbar.value)
			{
				_visTaskbar.percentWidth = 100;
					
				// The task bar should be at the bottom of the page
				if (!_visTaskbar.parent)
				{
					addChild(_visTaskbar);
//					PopUpManager.addPopUp(_visTaskbar, this);
				}
			}
			else
			{
				_visTaskbar.restoreAllComponents();

				if (_visTaskbar.parent)
				{
					removeChild(_visTaskbar);
//					PopUpManager.removePopUp(_visTaskbar);
				}
			}
		}
		
		private var _alreadyLoaded:Boolean = false;
		private var _defaultsFilename:String = null;
		/**
		 * loadPage():void
		 * @author abaumann
		 * This function will load all the tools, settings, etc
		 */
		private function loadPage():void
		{
			// We only want to do this page loading once
			if (_alreadyLoaded)
				return;
			
			if (!getConnectionName())
				enabled = false;
			
			// Name for the file that defines layout and tool settings.  This is extracted from a parameter passed to the HTML page.
			_defaultsFilename = getClientConfigFileName(); 	
	
			if (_defaultsFilename == null)
			{
				_defaultsFilename = "defaults.xml";
			}
			
			var noCacheHack:String = "?" + (new Date()).getTime(); // prevent flex from using cache
		
			WeaveAPI.URLRequestUtils.getURL(new URLRequest(_defaultsFilename + noCacheHack), handleDefaultsFileDownloaded, handleDefaultsFileFault);
			
			_alreadyLoaded = true;
		}
		
		private var _stateLoaded:Boolean = false;
		private function loadSessionState(state:XML):void
		{
			_defaultsXML = state;
			var i:int = 0;
			
			StageUtils.callLater(this,toggleMenuBar,null,false);
			
			if (!getConnectionName())
				enabled = true;
			
			// backwards compatibility:
			var stateStr:String = state.toXMLString();
			while (stateStr.indexOf("org.openindicators") >= 0)
			{
				stateStr = stateStr.replace("org.openindicators", "weave");
				state = XML(stateStr);
			}
			var tag:XML;
			for each (tag in state.descendants("OpenIndicatorsServletDataSource"))
				tag.setLocalName("WeaveDataSource");
			for each (tag in state.descendants("OpenIndicatorsDataSource"))
				tag.setLocalName("WeaveDataSource");
			for each (tag in state.descendants("WMSPlotter2"))
				tag.setLocalName("WMSPlotter");
			for each (tag in state.descendants("SessionedTextArea"))
			{
				tag.setLocalName("SessionedTextBox");
				tag.appendChild(<enableBorders>true</enableBorders>);
				tag.appendChild(<htmlText>{tag.textAreaString.text()}</htmlText>);
				tag.appendChild(<panelX>{tag.textAreaWindowX.text()}</panelX>);
				tag.appendChild(<panelY>{tag.textAreaWindowY.text()}</panelY>);
			}
			
			Weave.setSessionStateXML(_defaultsXML, true);
			fixCommonSessionStateProblems();

			if (_weaveMenu && _toolsMenu)
			{
				var reportsMenuItems:Array = getReportsMenuItems();
				if (reportsMenuItems.length > 0)
				{
					_weaveMenu.addSeparatorToMenu(_toolsMenu);
					
					for each(var reportMenuItem:WeaveMenuItem in reportsMenuItems)
					{
						_weaveMenu.addMenuItemToMenu(_toolsMenu, reportMenuItem);
					}
				}	
			}
			
			// handle dynamic changes to the session state that change what CSS file to use
			Weave.properties.cssStyleSheetName.addGroupedCallback(
				this,
				function():void
				{
					CSSUtils.loadStyleSheet(Weave.properties.cssStyleSheetName.value);
				},
				true
			);

			// generate the context menu items
			setupContextMenu();

			// Set the name of the CSS style we will be using for this application.  If weaveStyle.css is present, the style for
			// this application can be defined outside the code in a CSS file.
			this.styleName = "application";	
			
			_stateLoaded = true;
			
			//Sets the initial session state for an undo.
			var dynamicSess:DynamicState = new DynamicState();
			dynamicSess.sessionState = getSessionState(Weave.root);	
			dynamicSess.objectName = "Weave Session State 1";
			
			sessionStates[0] = dynamicSess;
		}
		
		/**
		 * This function will fix common problems that appear in saved session states.
		 */
		private function fixCommonSessionStateProblems():void
		{
			// An empty subset is not of much use.  If the subset is empty, reset it to include all records.
			var subset:KeyFilter = Weave.root.getObject(Weave.DEFAULT_SUBSET_KEYFILTER) as KeyFilter;
			if (subset.includeMissingKeys.value == false && subset.included.keys.length == 0 && subset.excluded.keys.length == 0)
				subset.includeMissingKeys.value = true;
		}
		
		private function handleWeaveListChange():void
		{
			if (Weave.root.childListCallbacks.lastObjectAdded is DraggablePanel)
				StageUtils.callLater(this,setupWindowMenu,null,false); // add panel to menu items
		}
		
		private function createColorHistogram():void
		{
			var name:String = Weave.root.generateUniqueName("ColorHistogramTool");
			var colorHistogram:HistogramTool = createGlobalObject(HistogramTool, name);
			colorHistogram.plotter.dynamicColorColumn.globalName = Weave.DEFAULT_COLOR_COLUMN;
		}
		
		private function createGlobalObject(classDef:Class, name:String = null):*
		{
			var className:String = getQualifiedClassName(classDef).split("::")[1];

			if (name == null)
				name = Weave.root.generateUniqueName(className);
			var object:* = Weave.root.requestObject(name, classDef, false);
			if (object is DraggablePanel)
				(object as DraggablePanel).restorePanel();
			// put panel in front
			Weave.root.setNameOrder([name]);

			return object;
		}
		
		private function setupSelectionsMenu():void
		{
			if (_weaveMenu && _selectionsMenu)
				SelectionManager.setupMenu(_weaveMenu, _selectionsMenu);
		}
		private function setupSubsetsMenu():void
		{
			if (_weaveMenu && _subsetsMenu)
				SubsetManager.setupMenu(_weaveMenu, _subsetsMenu);
		}

		private function get topPanel():DraggablePanel
		{
			var children:Array = Weave.root.getObjects(DraggablePanel);
			while (children.length)
			{
				var panel:DraggablePanel = children.pop() as DraggablePanel;
				if (panel.visible)
					return panel;
			}
			
			return null;
		}
		
		private function setupWindowMenu():void
		{
			if (!(_weaveMenu && _windowMenu && Weave.properties.enableWindowMenu.value))
				return;
			
			if (_windowMenu.children)
				_windowMenu.children.removeAll();
			
			
			var label:*;
			var click:Function;
			var enable:*;
			
			// minimize
			label = "Minimize This Window";
			click = function():void {
					if (topPanel)
						topPanel.minimizePanel();
				};
			enable = function():Boolean {
					return (topPanel && topPanel.minimizable.value);
				};
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(label, click, null, enable) );
			
			
			// maximize/restore
			label = function():String { 
					if ( topPanel && topPanel.maximized.value) 
						return 'Restore Panel Size'; 
					return 'Maximize This Window';
				};
			click = function():void { 
			    	if (topPanel)
			    		topPanel.toggleMaximized();
			    };
			enable = function():Boolean {
					return (topPanel && topPanel.maximizable.value);
				};
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(label, click, null, enable) );
			
			// close
			label = "Close This Window";
			click = function():void { 
					if (topPanel)
						topPanel.removePanel();
				};
			enable = function():Boolean {
					return (topPanel && topPanel.closeable.value);
				};
			
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(label, click, null, enable) );
				
			// Minimize All Windows: Get a list of all panels and call minimizePanel() on each sequentially
			click = function():void {
				var children:Array = Weave.root.getObjects(DraggablePanel);
				while (children.length)
				{
					var panel:DraggablePanel = children.pop() as DraggablePanel;
					if(panel.minimizable.value) panel.minimizePanel();
				}
			};
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem("Minimize All Windows", click, null, Weave.properties.enableMinimizeAllWindows.value) );
			
			// Restore all minimized windows: Get a list of all panels and call restorePanel() on each sequentially
			click = function():void {
				var children:Array = Weave.root.getObjects(DraggablePanel);
				while(children.length)
				{
					panel = children.shift() as DraggablePanel;
					panel.restorePanel();
				}
			};
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem("Restore All Mimimized Windows", click, null, Weave.properties.enableRestoreAllMinimizedWindows.value ));
			
			// Close All Windows: Get a list of all panels and call removePanel() on each sequentially
			click = function():void {
				var children:Array = Weave.root.getObjects(DraggablePanel);
				while(children.length)
				{
					panel = children.pop() as DraggablePanel;
					panel.removePanel();
				}
			};
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem("Close All Windows", click, null, Weave.properties.enableCloseAllWindows.value)) ;
			
			// cascade windows
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem("Cascade All Windows", cascadeWindows, null, Weave.properties.enableCascadeAllWindows.value ));
			
			// tile windows
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem("Tile All Windows", tileWindows, null, Weave.properties.enableTileAllWindows.value )) ;
			
			
			_weaveMenu.addMenuItemToMenu(_windowMenu, new WeaveMenuItem(
				function():String { 
					if ( stage.displayState == StageDisplayState.FULL_SCREEN) 
						return 'Exit Fullscreen'; 
					
					return 'Go Fullscreen';
				},
				function():void{
					if (stage.displayState == StageDisplayState.NORMAL )
					{
						// set full screen display
						stage.displayState = StageDisplayState.FULL_SCREEN;
					}
					else
					{
						// set normal display
						stage.displayState = StageDisplayState.NORMAL;
					}
				}, 
				null,
				Weave.properties.enableGoFullscreen.value) );
			_weaveMenu.addSeparatorToMenu(_windowMenu);
			//_visMenu.addSeparatorToMenu(windowMenu);
			//_visMenu.addMenuItemToMenu("Window", new VisMenuItem("[submenu] Load Window Layout", null));
			//_visMenu.addMenuItemToMenu("Window", new VisMenuItem("[submenu] Save Window Layout", null));
			
			var panels:Array = Weave.root.getObjects(DraggablePanel);
			for (var i:int = 0; i < panels.length; i++)
			{	
				var panel:DraggablePanel = panels[i] as DraggablePanel;
				var newToolMenuItem:WeaveMenuItem = createWindowMenuItem(panel, _weaveMenu, _windowMenu);
				if (_weaveMenu)
					_weaveMenu.addMenuItemToMenu(_windowMenu, newToolMenuItem);
			}
		}
		
		private function createWindowMenuItem(panel:DraggablePanel, destinationMenuBar:WeaveMenuBar, destinationMenuItem:WeaveMenuItem):WeaveMenuItem
		{
			var newToolMenuItem:WeaveMenuItem = new WeaveMenuItem( panel.title,
																   function ():void {
																   		if(panel.minimizedComponentVersion != null)
																   			panel.minimizedComponentVersion.restoreFunction();
																   		else
																			panel.restorePanel();
																	});
			 
			newToolMenuItem.type = WeaveMenuItem.TYPE_RADIO;
			newToolMenuItem.groupName = "activeWindows";
			newToolMenuItem.toggledFunction = function ():Boolean {
				return newToolMenuItem.relevantItemPointer == topPanel;
			};
			newToolMenuItem.relevantItemPointer = panel;
			newToolMenuItem.labelFunction = function ():String 
											{ 
												var menuLabel:String = "untitled ";
												if(panel.title.replace(" ", "").length > 0) 
													menuLabel = panel.title;
												else
													menuLabel += " window";
													
												
												if(panel.minimized.value)
												{
													menuLabel = ">\t" + menuLabel;
												}
													
												return menuLabel;
											};
			
			addEventListener(FlexEvent.REMOVE, function(e:Event):void {
				if(destinationMenuBar && destinationMenuItem)
					destinationMenuBar.removeMenuItemFromMenu(newToolMenuItem, destinationMenuItem);
			});
										
			return newToolMenuItem;
		}

		// Handle a file fault when trying to download the defaults file -- for now, this just pops up a window showing that the file could not be downloaded
		private function handleDefaultsFileFault(event:FaultEvent, token:Object = null):void
		{
			//if connection name exists then user might be creating a new config file.
			if (getConnectionName() == '' || getConnectionName() == null)
			{
				Alert.show("No data specified for page or defaults file not found.  Please provide a defaults.xml file that specifies what data to show when no '?defaults=filename.xml' is specified in page URL.", "Missing Config URL");
			}		
		}

		/**
		 * @author kmanohar
		 * <br/>This function arranges all DraggablePanels along a diagonal
		 */		
		private function cascadeWindows():void
		{
			var panels:Array = getWindowsOnStage();
			if(!panels.length) return;
			
			var dpanel:DraggablePanel;
			dpanel = panels[panels.length-1] as DraggablePanel;
			
			dpanel.panelWidth.value = "50%";
			dpanel.panelHeight.value = "50%";
			
			var increment:Number = 50/panels.length;
			var dist:Number = 0 ;
			
			for( var i:int = 0; i < panels.length ; i++ ) 
			{
				dpanel = panels[i] as DraggablePanel;
				dpanel.panelX.value = dist.toString()+"%";
				dpanel.panelY.value = dist.toString()+"%";
				dpanel.panelWidth.value = "50%" ;
				dpanel.panelHeight.value = "50%" ;
				dist += increment;
			}
		}
		
		/**
		 * @author kmanohar
		 * <br/> This function tiles all the DraggablePanels on stage
		 * <br/> TO DO: create a ui for this so the user can specify how to divide the stage
		 */		
		private function tileWindows():void
		{
			var panels:Array = getWindowsOnStage();
 			var numPanels:uint = panels.length;
			if(!numPanels) return;
			
			var gridLength:Number = Math.ceil(Math.sqrt(numPanels));
			var i:Number = gridLength; var j:Number = gridLength;
			var factor1:uint = i; var factor2:uint = j;
			
			if( numPanels == 2) 
			{
				factor1 = 2;
				factor2 = 1;
			}
			else if( (gridLength*gridLength != numPanels) && (numPanels != 1) )
			{
				/*if( !(numPanels % 5) );
				else if( !(numPanels % 3));	*/
				if( numPanels % 2 )numPanels++;
				var minDiff:Number = numPanels;
				while( i < numPanels )
				{
					j = gridLength;
					while( j >= 1 )
					{
						if(i*j == numPanels) 
							if( (i-j <= minDiff) ) {
								minDiff = i-j ;
								factor1 = i; factor2 = j;
							}
						j--;
					}
					i++;
				}
			}
			
			//trace( factor1 + " " + factor2 + " " + numPanels);
			
			var dp:DraggablePanel;
			var xPos:Number = 0; var yPos:Number = 0 ;
			var width:Number = 100/((stage.stageWidth > stage.stageHeight) ? factor1 : factor2);
			var height:Number = 100/((stage.stageWidth > stage.stageHeight) ? factor2 : factor1);
			for( i = 0; i < panels.length; i++ )
			{
				dp = panels[i] as DraggablePanel;
				dp.panelX.value = xPos.toString() + "%";
				dp.panelY.value = yPos.toString() + "%";
				dp.panelWidth.value = width.toString() + "%";
				dp.panelHeight.value = height.toString() + "%";
				xPos += width;
				if(xPos >= 100) xPos = 0;
				if( !xPos) yPos += height ;
			}
		}
		
		/**
		 * @author kmanohar
		 * @return an Array containing all DraggablePanels on stage that are not minimized
		 * 
		 */		
		private function getWindowsOnStage():Array
		{
			var panels:Array = Weave.root.getObjects(DraggablePanel);
			var panelsOnStage:Array = [];
			var panel:DraggablePanel;
			for( var i:int = 0; i < panels.length; i++ )
			{
				panel = panels[i] as DraggablePanel;
				if(!panel.minimized.value) 
					panelsOnStage.push(panels[i]);
			}
			return panelsOnStage;
		}
		
		// The tool "grid" (rows and columns) are used in a non-dynamic view -- The _toolColumnSpace is a vertical box that 
		// holds all the columns of tools
		private var _toolColumnSpace:VDividedBox = null;
		
		// This array keeps track of the tools that are active in the display
		private var _activeTools:Array = [];

		
		/**
		 * handleDefaultsFileDownloaded(event:ResultEvent):void
		 * @author abaumann
		 * This function handles parsing the defaults file once it has downloaded.  Ideally this contains very little specific information,
		 * other classes should be able to be restored from the defaults
		 */
		private function handleDefaultsFileDownloaded(event:ResultEvent, token:Object = null):void
		{
			var xml:XML = null;
			try
			{
				xml = XML(event.result);
			}
			catch (e:Error)
			{
				ErrorManager.reportError(e);
			}
			if (xml)
				loadSessionState(xml);
			if (getEditableSettingFromURL())
			{
				Weave.properties.enableMenuBar.value = true;
				Weave.properties.enableSessionMenu.value = true;
				Weave.properties.enableSessionEdit.value = true;
				Weave.properties.enableSessionImport.value = true;
				Weave.properties.enableSessionExport.value = true;
				Weave.properties.enableUserPreferences.value = true;
			}
			
			// enable JavaScript API after initial session state has loaded.
			WeaveAPI.initializeExternalInterface();
		}
		

		
		/** BEGIN CONTEXT MENU CODE **/
		private var _printToolMenuItem:ContextMenuItem = null;
		
		/**
		 * setupContextMenu():void
		 * @author abaumann
		 * This function creates the context menu for this application by getting context menus from each
		 * class that defines them -- TODO: generalize this better...
		 */
		private function setupContextMenu():void
		{ 
			//if (contextMenu == null)
				contextMenu = new ContextMenu();
			
			// Hide the default Flash menu
			contextMenu.hideBuiltInItems();
			
			CustomContextMenuManager.removeAllContextMenuItems();
			
			if (Weave.properties.enableRightClick.value)
			{
				// Add item for the DataTableTool
				//DataTableTool.createContextMenuItems(this);
				
				// Add item for the DatasetLoader
				//DatasetLoader.createContextMenuItems(this);
				
				if (Weave.properties.enableSubsetControls.value)
				{
					// Add context menu item for selection related items (subset creation, etc)	
					KeySetContextMenuItems.createContextMenuItems(this);
				}
				
				SessionedTextBox.createContextMenuItems(this);
				
					
				//HelpPanel.createContextMenuItems(this);
				if (Weave.properties.dataInfoURL.value)
					addLinkContextMenuItem("Show Information About This Dataset...", Weave.properties.dataInfoURL.value);
				
				// Add context menu item for VisTools (right now this is exporting of an image, will also have printing of an image, etc -- for
				// one tool at a time)
				createExportToolImageContextMenuItem();
				_printToolMenuItem = CustomContextMenuManager.createAndAddMenuItemToDestination("Print Application Image", this, handleContextMenuItemSelect, "4 exportMenuItems");
				
				
				// Add context menu items for handling search queries
				SearchEngineUtils.createContextMenuItems(this);
				// Additional record queries can be defined in the defaults file.  Here they are extracted and added as context menu items with their
				// associated actions.
				if (_defaultsXML)
				{
					for(var i:int = 0; i < _defaultsXML.recordQuery.length(); i++)
					{
						SearchEngineUtils.addSearchQueryContextMenuItem(_defaultsXML.recordQuery[i], this);	
					}
				}
			}
		}

		// Create the context menu items for exporting panel images.  
		private var _panelPrintContextMenuItem:ContextMenuItem = null;
		protected var panelSettingsContextMenuItem:ContextMenuItem = null;
		private function createExportToolImageContextMenuItem():Boolean
		{				
			if(Weave.properties.enableExportToolImage.value)
			{
				// Add a listener to this destination context menu for when it is opened
				contextMenu.addEventListener(ContextMenuEvent.MENU_SELECT, handleContextMenuOpened);
				
				// Create a context menu item for printing of a single tool with title and logo
				_panelPrintContextMenuItem = CustomContextMenuManager.createAndAddMenuItemToDestination(
						"Print/Export Panel Image...", 
						this,
						function(event:ContextMenuEvent):void { printOrExportImage(_panelToExport); },
						"4 exportMenuItems"
					);
				// By default this menu item is disabled so that it does not show up unless we right click on a tool
				_panelPrintContextMenuItem.enabled = false;
				
				return true;
			}
			
			return false;
		}
		// Handler for when the context menu is opened.  In here we will keep track of what tool we were over when we right clicked so 
		// that we can export an image of just this tool.  We also change the text in the context menu item for exporting an image of 
		// this tool so it  says the name of the tool to export.
		private var _panelToExport:DraggablePanel = null;
		private function handleContextMenuOpened(event:ContextMenuEvent):void
		{
			// When the context menu is opened, save a pointer to the active tool, this is the tool we want to export an image of
			_panelToExport = DraggablePanel.activePanel;
			
			// If this tool is valid (we are over a tool), then we want this menu item enabled, otherwise don't allow users to choose it
			if(_panelToExport != null)
			{
				_panelPrintContextMenuItem.caption = "Print/Export " + _panelToExport.title + " Image...";
				_panelPrintContextMenuItem.enabled = true;
			}
			else
			{
				_panelPrintContextMenuItem.caption = "Print/Export Panel Image...";
				_panelPrintContextMenuItem.enabled = false;	
			}
		}
		
		/** 
		 *  Static methods to encapsulate the list of reports within the ObjectRepository
		 *  addReportsToMenu loops through the reports in the Object Repository and 
		 *     adds them to the tools menu
		 * */
		public static function getReportsMenuItems():Array
		{
			var reportsMenuItems:Array = [];
			//add reports to tools menu
			for each (var report:WeaveReport in Weave.root.getObjects(WeaveReport))
			{
				reportsMenuItems.push(new WeaveMenuItem(Weave.root.getName(report), WeaveReport.requestReport, [report]));
			}	
			
			return reportsMenuItems;
		}
		
		private var _sessionFileLoader:FileReference = null;
		private var _sessionFileSaver:FileReference = null;
		private function handleImportSessionState():void
		{			
			if (_sessionFileLoader == null)
			{
				_sessionFileLoader = new FileReference();
				
				_sessionFileLoader.addEventListener(Event.SELECT,   function (e:Event):void { _sessionFileLoader.load(); _defaultsFilename = _sessionFileLoader.name; } );
				_sessionFileLoader.addEventListener(Event.COMPLETE, function (e:Event):void {loadSessionState( XML(e.target.data) );} );
			}
			
			_sessionFileLoader.browse([new FileFilter("XML", "*.xml")]);
		}
		
		private function handleExportSessionState():void
		{		
			
			var exportSessionStatePanel:ExportSessionStatePanel = new ExportSessionStatePanel();
			
			exportSessionStatePanel = PopUpManager.createPopUp(this,ExportSessionStatePanel,false) as ExportSessionStatePanel;
			PopUpManager.centerPopUp(exportSessionStatePanel);
			
//			if (_sessionFileSaver == null)
//			{
//				_sessionFileSaver = new FileReference();
//			}
//			
//			// Create a date that we can append to the end of each file to make them unique
//   			var date:Date = new Date();
//   			var dateString:String = date.fullYear +"."+ date.month +"."+ date.day +" "+ date.time;
//
//   			_sessionFileSaver.save(Weave.getSessionStateXML(), "weave session state " + dateString + ".xml");
		}
		
		public function printOrExportImage(component:UIComponent):void
		{
			if (!component)
				return;
			
			var visMenuVisible:Boolean    = (_weaveMenu ? _weaveMenu.visible : false);
			var visTaskbarVisible:Boolean = (_visTaskbar ? _visTaskbar.visible : false);
			
			if (_weaveMenu)    _weaveMenu.visible    = false;
			if (_visTaskbar) _visTaskbar.visible = false;

			//initialize the print format
			var printPopUp:PrintFormat = new PrintFormat();
   			printPopUp = PopUpManager.createPopUp(this,PrintFormat,true) as PrintFormat;
   			PopUpManager.centerPopUp(printPopUp);
   			printPopUp.applicationTitle = Weave.properties.pageTitle.value;
   			//add current snapshot to Print Format
			printPopUp.componentToScreenshot = component;
			
			if (_weaveMenu)  _weaveMenu.visible    = visMenuVisible;
			if (_visTaskbar) _visTaskbar.visible = visTaskbarVisible;	
		}
		
		public function updatePageTitle():void
		{
			ExternalInterface.call("setTitle", Weave.properties.pageTitle.value);
		}
		
		
		// Add a context menu item that goes to an associated url in a new browser window/tab
		private function addLinkContextMenuItem(text:String, url:String, separatorBefore:Boolean=false):void
		{
			CustomContextMenuManager.createAndAddMenuItemToDestination(text, 
															  this, 
                                                              function(e:Event):void { navigateToURL(new URLRequest(url), "_blank"); },
                                                              "linkMenuItems");	
		}

			
		// TODO: This should be removed -- ideally VisApplication has no context menu items itself, only other classes do
		protected function handleContextMenuItemSelect(event:ContextMenuEvent):void
		{
			if (event.currentTarget == _printToolMenuItem)
   			{
   				printOrExportImage(this);
   			}
   			
		}
		/** END CONTEXT MENU CODE **/

		
		public function drawConnection(fromUI:UIComponent,toUI:UIComponent=null,clear:Boolean=true):void
		{
			var fromPoint:Point = fromUI.localToGlobal(new Point(0,0));
			var toPoint:Point = new Point();
			
			if (toUI)
				toPoint = toUI.localToGlobal(new Point(0,0));
			else{
				var toPointX:Number = 0;
				var toPointY:Number = 0;
				
				if (fromPoint.y <= mouseY)
					toPointY = mouseY-12;
				else 
					toPointY = mouseY+12;
				
				if (fromPoint.x <= mouseX)
					toPointX= mouseX-12;
				else 
					toPointX= mouseX+12;
						
				toPoint = new Point(toPointX,toPointY);
			}
				
			
			// start curve anchor at halfway point between origin and destination
			var curveAnchor:Point = new Point(
				(fromPoint.x + fromPoint.x)/2,
				(toPoint.y + toPoint.y)/2);
			
//			VisApplication.instance.rawChildren.addChild(_connectionsLayer);
//			
//			if (clear)
//				_connectionsLayer.graphics.clear();
//			
//			_connectionsLayer.graphics.lineStyle(4,0x8AA37B,1);
//			
//			//DrawUtils.drawCurvedLine(_connectionsLayer.graphics,fromPoint.x,fromPoint.y,toPoint.x,toPoint.y,2);
//			_connectionsLayer.graphics.moveTo(fromPoint.x,fromPoint.y);
//			_connectionsLayer.graphics.curveTo(curveAnchor.x,curveAnchor.y,toPoint.x,toPoint.y);

		}
		
//		public function drawConnections(fromUI:UIComponent,toUIs:Array):void
//		{
//			_connectionsLayer.graphics.clear();
//			
//			for each(var ui:UIComponent in toUIs)
//			{
//				drawConnection(fromUI,ui,false);
//			}
//			
//		}
		
//		public function removeConnections():void
//		{
//			_connectionsLayer.graphics.clear();			
//		}
		
		
		private function testColumn(column:IAttributeColumn):void
		{
			var key:IQualifiedKey;
			var keys:Array = column ? column.keys : [];
			trace(getQualifiedClassName(column), column);
			trace("keys: "+keys);
			for each (key in keys)
			{
				var debug:String = "key = "+key.keyType+'#'+key.localName+":";
				for each (var type:Class in [null, Number, String, Boolean])
				{
					var value:* = column.getValueFromKey(key, type);
					var typeStr:String = type ? String(type) : '('+getQualifiedClassName(value)+')';
					debug += "\n\t"+typeStr+":\t"+value;
				}
				trace(debug);
			}
		}
		
		private function trace(...args):void
		{
			DebugUtils.debug_trace(VisApplication, args);
		}	
	}
}