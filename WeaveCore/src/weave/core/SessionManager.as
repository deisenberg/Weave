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

package weave.core
{
	import flash.display.DisplayObject;
	import flash.display.DisplayObjectContainer;
	import flash.utils.Dictionary;
	import flash.utils.describeType;
	import flash.utils.getQualifiedClassName;
	
	import mx.binding.utils.BindingUtils;
	import mx.binding.utils.ChangeWatcher;
	import mx.core.UIComponent;
	import mx.core.mx_internal;
	import mx.utils.ObjectUtil;
	
	import weave.api.WeaveAPI;
	import weave.api.core.ICallbackCollection;
	import weave.api.core.IDisposableObject;
	import weave.api.core.ILinkableCompositeObject;
	import weave.api.core.ILinkableDynamicObject;
	import weave.api.core.ILinkableHashMap;
	import weave.api.core.ILinkableObject;
	import weave.api.core.ILinkableVariable;
	import weave.api.core.ISessionManager;

	use namespace weave_internal;

	/**
	 * This is a collection of core functions in the Weave session framework.
	 * 
	 * @author adufilie
	 */
	public class SessionManager implements ISessionManager
	{
		/**
		 * This function will create a new instance of the specified child class and register it as a child of the parent.
		 * If a callback function is given, the callback will be added to the child and cleaned up when the parent is disposed of.
		 * 
		 * Example usage:   public const foo:LinkableNumber = newLinkableChild(this, LinkableNumber, handleFooChange);
		 * 
		 * @param linkableParent A parent ILinkableObject to create a new child for.
		 * @param linkableChildType The class definition that implements ILinkableObject used to create the new child.
		 * @param callback A callback with no parameters that will be added to the child that will run before the parent callbacks are triggered, or during the next ENTER_FRAME event if a grouped callback is used.
		 * @param useGroupedCallback If this is true, addGroupedCallback() will be used instead of addImmediateCallback().
		 * @return The new child object.
		 */
		public function newLinkableChild(linkableParent:Object, linkableChildType:Class, callback:Function = null, useGroupedCallback:Boolean = false):*
		{
			if (!(linkableParent is ILinkableObject))
				throw new Error("newLinkableChild(): Parent does not implement ILinkableObject.");
			
			var childQName:String = getQualifiedClassName(linkableChildType);
			if (!ClassUtils.classImplements(childQName, ILinkableObjectQualifiedClassName))
				throw new Error("newLinkableChild(): Child class does not implement ILinkableObject.");
			
			var linkableChild:ILinkableObject = new linkableChildType() as ILinkableObject;
			return registerLinkableChild(linkableParent, linkableChild, callback, useGroupedCallback);
		}
		
		/**
		 * This function tells the SessionManager that the session state of the specified child should appear in the
		 * session state of the specified parent, and the child should be disposed of when the parent is disposed.
		 * 
		 * There is one other requirement for the child session state to appear in the parent session state -- the child
		 * must be accessible through a public variable of the parent or through an accessor function of the parent.
		 * 
		 * This function will add callbacks to the sessioned children that cause the parent callbacks to run.
		 * 
		 * If a callback function is given, the callback will be added to the child and cleaned up when the parent is disposed of.
		 * 
		 * Example usage:   public const foo:LinkableNumber = registerLinkableChild(this, someLinkableNumber, handleFooChange);
		 * 
		 * @param linkableParent A parent ILinkableObject that the child will be registered with.
		 * @param linkableChild The child ILinkableObject to register as a child.
		 * @param callback A callback with no parameters that will be added to the child that will run before the parent callbacks are triggered, or during the next ENTER_FRAME event if a grouped callback is used.
		 * @param useGroupedCallback If this is true, addGroupedCallback() will be used instead of addImmediateCallback().
		 * @return The linkableChild object that was passed to the function.
		 */
		public function registerLinkableChild(linkableParent:Object, linkableChild:ILinkableObject, callback:Function = null, useGroupedCallback:Boolean = false):*
		{
			if (!(linkableParent is ILinkableObject))
				throw new Error("registerLinkableChild(): Parent does not implement ILinkableObject.");
			if (!(linkableChild is ILinkableObject))
				throw new Error("registerLinkableChild(): Child does not implement ILinkableObject.");
			if (linkableParent == linkableChild)
				throw new Error("registerLinkableChild(): Invalid attempt to register sessioned property having itself as its parent");
			
			// add a callback that will be cleaned up when the parent is disposed of.
			// add this callback BEFORE registering the child, so this callback triggers first.
			if (callback != null)
			{
				var cc:ICallbackCollection = getCallbackCollection(linkableChild);
				if (useGroupedCallback)
					cc.addGroupedCallback(linkableParent as ILinkableObject, callback);
				else
					cc.addImmediateCallback(linkableParent as ILinkableObject, callback);
			}
			
			// if the child doesn't have an owner yet, this parent is the owner of the child
			// and the child should be disposed when the parent is disposed.
			// registerDisposedChild() also initializes the required Dictionaries.
			registerDisposableChild(linkableParent, linkableChild);

			// only continue if the child is not already registered with the parent
			if (childToParentDictionaryMap[linkableChild][linkableParent] === undefined)
			{
				// remember this child-parent relationship
				childToParentDictionaryMap[linkableChild][linkableParent] = true;
				parentToChildDictionaryMap[linkableParent][linkableChild] = true;
				
				// make child changes trigger parent callbacks
				var parentCC:ICallbackCollection = getCallbackCollection(linkableParent as ILinkableObject);
				getCallbackCollection(linkableChild).addImmediateCallback(linkableParent, parentCC.triggerCallbacks);
			}

			return linkableChild;
		}
		
		/**
		 * This function will create a new instance of the specified child class and register it as a child of the parent.
		 * The child will be disposed when the parent is disposed.
		 * 
		 * Example usage:   public const foo:LinkableNumber = newDisposableChild(this, LinkableNumber);
		 * 
		 * @param disposableParent A parent ILinkableObject to create a new child for.
		 * @param disposableChildType The class definition that implements ILinkableObject used to create the new child.
		 * @return The new child object.
		 */
		public function newDisposableChild(disposableParent:Object, disposableChildType:Class):*
		{
			return registerDisposableChild(disposableParent, new disposableChildType());
		}
		
		/**
		 * This will register a child of a parent and cause the child to be disposed when the parent is disposed.
		 * If the child already has a registered owner, this function has no effect.
		 * 
		 * Example usage:   public const foo:LinkableNumber = registerDisposableChild(this, someLinkableNumber);
		 * 
		 * @param disposableParent A parent disposable object that the child will be registered with.
		 * @param disposableChild The disposable object to register as a child of the parent.
		 * @return The linkableChild object that was passed to the function.
		 */
		public function registerDisposableChild(disposableParent:Object, disposableChild:Object):*
		{
			// if this parent has no owner-to-child mapping, initialize it now with parent-to-child mapping
			if (ownerToChildDictionaryMap[disposableParent] === undefined)
			{
				ownerToChildDictionaryMap[disposableParent] = new Dictionary(true); // weak links to be GC-friendly
				parentToChildDictionaryMap[disposableParent] = new Dictionary(true); // weak links to be GC-friendly
			}
			// if this child has no owner yet...
			if (childToOwnerMap[disposableChild] === undefined)
			{
				// make this first parent the owner
				childToOwnerMap[disposableChild] = disposableParent;
				ownerToChildDictionaryMap[disposableParent][disposableChild] = true;
				// initialize the parent dictionary for this child
				childToParentDictionaryMap[disposableChild] = new Dictionary(true); // weak links to be GC-friendly
			}
			return disposableChild;
		}
		
		/**
		 * Use this function with care.  This will remove child objects from the session state of a parent and
		 * stop the child from triggering the parent callbacks.
		 * @param parent A parent that the specified child objects were previously registered with.
		 * @param child The child object to unregister from the parent.
		 */
		weave_internal function unregisterLinkableChild(parent:ILinkableObject, child:ILinkableObject):void
		{
			removeLinkableChildrenFromSessionState(parent, child);
			getCallbackCollection(child).removeCallback(getCallbackCollection(parent).triggerCallbacks);
		}
		
		/**
		 * Use this function with care.  This will remove child objects from the session state of a parent.  This
		 * means the children will no longer be "sessioned."  The child objects will continue to trigger the callbacks
		 * of the parent object, but they will no longer be considered a part of the parent's session state.  If you
		 * are not careful, this will break certain functionalities that depend on the session state of the parent.
		 * @param parent A parent that the specified child objects were previously registered with.
		 * @param child The first child object to remove from the session state of the parent.
		 * @param moreChildren Additional child objects to remove from the session state.
		 */
		public function removeLinkableChildrenFromSessionState(parent:ILinkableObject, child:ILinkableObject, ...moreChildren):void
		{
			if (parent == null || child == null)
			{
				var error:Error = new Error("SessionManager.removeLinkableChildrenFromSessionState(): Parameters to this function cannot be null.");
				ErrorManager.reportError(error);
				return;
			}
			if (childToParentDictionaryMap[child] != undefined)
				delete childToParentDictionaryMap[child][parent];
			if (parentToChildDictionaryMap[parent] != undefined)
				delete parentToChildDictionaryMap[parent][child];
			for each (child in moreChildren)
				removeLinkableChildrenFromSessionState(parent, child);
		}
		
		/**
		 * This function will return all the child objects that have been registered with a parent.
		 * @param parent A parent object to get the registered children of.
		 * @return An Array containing a list of linkable objects that have been registered as children of the specified parent.
		 *         This list includes all children that have been registered, even those that do not appear in the session state.
		 */
		weave_internal function getRegisteredChildren(parent:ILinkableObject):Array
		{
			var result:Array = [];
			if (parentToChildDictionaryMap[parent] != undefined)
				for (var key:* in parentToChildDictionaryMap[parent])
					result.push(key);
			return result;
		}

		/**
		 * This function gets the owner of a linkable object.  The owner of an object is defined as its first registered parent.
		 * @param child An ILinkableObject that was registered as a child of another ILinkableObject.
		 * @return The owner of the child object (the first parent that was registered with the child), or null if the child has no owner.
		 */
		public function getLinkableObjectOwner(child:ILinkableObject):ILinkableObject
		{
			return childToOwnerMap[child] as ILinkableObject;
		}

		/**
		 * This function checks if a parent-child relationship exists between two ILinkableObjects
		 * and the child appears in the session state of the parent.
		 * @param parent A suspected parent object.
		 * @param child A suspected child object.
		 * @return true if the child is registered as a child of the parent.
		 */
		weave_internal function isChildInSessionState(parent:ILinkableObject, child:ILinkableObject):Boolean
		{
			return childToParentDictionaryMap[child] != undefined && childToParentDictionaryMap[child][parent];
		}
		
		/**
		 * This function will copy the session state from one sessioned object to another.
		 * If the two objects are of different types, the behavior of this function is undefined.
		 * @param source A sessioned object to copy the session state from.
		 * @param source A sessioned object to copy the session state to.
		 */
		public function copySessionState(source:ILinkableObject, destination:ILinkableObject):void
		{
			var sessionState:Object = getSessionState(source);
			setSessionState(destination, sessionState, true);
		}

		/**
		 * @param linkableObject An object containing sessioned properties (sessioned objects may be nested).
		 * @param newState An object containing the new values for sessioned properties in the sessioned object.
		 * @param removeMissingDynamicObjects If true, this will remove any properties from an ILinkableCompositeObject that do not appear in the session state.
		 */
		public function setSessionState(linkableObject:ILinkableObject, newState:Object, removeMissingDynamicObjects:Boolean):void
		{
			if (linkableObject == null)
			{
				var error:Error = new Error("SessionManager.setSessionState(): linkableObject cannot be null.");
				ErrorManager.reportError(error);
				return;
			}

			// special cases:
			if (linkableObject is ILinkableVariable)
			{
				(linkableObject as ILinkableVariable).setSessionState(newState);
				return;
			}
			if (linkableObject is ILinkableCompositeObject)
			{
				(linkableObject as ILinkableCompositeObject).setSessionState(newState as Array, removeMissingDynamicObjects);
				return;
			}

			if (newState == null)
				return;

			// delay callbacks before setting session state
			var objectCC:ICallbackCollection = getCallbackCollection(linkableObject);
			objectCC.delayCallbacks();

			// set session state
			var deprecatedNames:Array = getLinkablePropertyNames(linkableObject, true);
			var propertyNames:Array = getLinkablePropertyNames(linkableObject);
			for each (var names:Array in [deprecatedNames, propertyNames])
			{
				for each (var name:String in names)
				{
					if (!(newState as Object).hasOwnProperty(name))
						continue;
					
					var property:ILinkableObject = null;
					try
					{
						property = linkableObject[name] as ILinkableObject;
					}
					catch (e:Error)
					{
						trace('SessionManager.setSessionState(): Unable to get property "'+name+'" of class "'+getQualifiedClassName(linkableObject)+'"',e.getStackTrace());
					}

					if (property == null)
						continue;

					// skip this property if it was not registered as a linkable child of the sessionedObject.
					if (childToParentDictionaryMap[property] === undefined || childToParentDictionaryMap[property][linkableObject] === undefined)
						continue;
						
					setSessionState(property, newState[name], removeMissingDynamicObjects);
				}
			}
			
			// resume callbacks after setting session state
			objectCC.resumeCallbacks();
		}
		
		/**
		 * @param linkableObject An object containing sessioned properties (sessioned objects may be nested).
		 * @return An object containing the values from the sessioned properties.
		 */
		public function getSessionState(linkableObject:ILinkableObject):Object
		{
			if (linkableObject == null)
			{
				var error:Error = new Error("SessionManager.getSessionState(): linkableObject cannot be null.");
				ErrorManager.reportError(error);
				return null;
			}
			
			var result:Object = internalGetSessionState(linkableObject, new Dictionary(true));
			//trace("getSessionState " + getQualifiedClassName(sessionedObject).split("::")[1] + ObjectUtil.toString(result));
			return result;
		}
		
		/**
		 * This function is for internal use only.
		 * @param sessionedObject An object containing sessioned properties (sessioned objects may be nested).
		 * @param ignoreList A dictionary that keeps track of which objects this function has already traversed.
		 * @return An object containing the values from the sessioned properties.
		 */
		private function internalGetSessionState(sessionedObject:ILinkableObject, ignoreList:Dictionary):Object
		{
			// use ignore list to prevent infinite recursion
			ignoreList[sessionedObject] = true;
			
			// special cases:
			if (sessionedObject is ILinkableVariable)
				return (sessionedObject as ILinkableVariable).getSessionState();
			if (sessionedObject is ILinkableCompositeObject)
				return (sessionedObject as ILinkableCompositeObject).getSessionState();

			// first pass: get property names
			var propertyNames:Array = getLinkablePropertyNames(sessionedObject);
			var resultNames:Array = [];
			var resultProperties:Array = [];
			var i:int;
			//trace("getting session state for "+getQualifiedClassName(sessionedObject),"propertyNames="+propertyNames);
			for (i = 0; i < propertyNames.length; i++)
			{
				var name:String = propertyNames[i];
				var property:ILinkableObject = null;
				try
				{
					property = sessionedObject[name] as ILinkableObject;
				}
				catch (e:Error)
				{
					trace('SessionManager.internalGetSessionState(): Unable to get property "'+name+'" of class "'+getQualifiedClassName(sessionedObject)+'"',e.getStackTrace());
				}
				// first pass: set result[name] to the ILinkableObject
				if (property != null && ignoreList[property] === undefined)
				{
					// skip this property if it was not registered as a linkable child of the sessionedObject.
					if (childToParentDictionaryMap[property] === undefined || childToParentDictionaryMap[property][sessionedObject] === undefined)
						continue;
					// only include this property in the session state once
					ignoreList[property] = true;
					resultNames.push(name);
					resultProperties.push(property);
				}
				else
				{
					//trace("skipped property",name,property,ignoreList[property]);
				}
			}
			// second pass: get values from property names
			var result:Object = new Object();
			for (i = 0; i < resultNames.length; i++)
			{
				result[resultNames[i]] = internalGetSessionState(resultProperties[i], ignoreList);
				//trace("getState",getQualifiedClassName(sessionedObject),resultNames[i],result[resultNames[i]]);
			}
			return result;
		}
		
		/**
		 * This maps a qualified class name to an Array of names of sessioned properties contained in that class.
		 */
		private const classNameToSessionedPropertyNamesMap:Object = new Object();
		/**
		 * This maps a qualified class name to an Array of names of deprecated sessioned properties contained in that class.
		 */
		private const classNameToDeprecatedSessionedPropertyNamesMap:Object = new Object();

		/**
		 * This function will return all the descendant objects that implement ILinkableObject.
		 * If the filter parameter is specified, the results will contain only those objects that extend or implement the filter class.
		 * @param root A root object to get the descendants of.
		 * @param filter An optional Class definition which will be used to filter the results.
		 * @return An Array containing a list of descendant objects.
		 */
		weave_internal function getDescendants(root:ILinkableObject, filter:Class = null):Array
		{
			if (root == null)
			{
				var error:Error = new Error("SessionManager.getDescendants(): root cannot be null.");
				ErrorManager.reportError(error);
				return [];
			}

			var result:Array = [];
			internalGetDescendants(result, root, filter, new Dictionary(true), int.MAX_VALUE);
			// don't include root object
			if (result.length > 0 && result[0] == root)
				result.shift();
			return result;
		}
		private function internalGetDescendants(output:Array, root:ILinkableObject, filter:Class, ignoreList:Dictionary, depth:int):void
		{
			if (root == null || ignoreList[root] != undefined)
				return;
			ignoreList[root] = true;
			if (filter == null || root is filter)
				output.push(root);
			if (--depth <= 0)
				return;
			
			var object:ILinkableObject;
			var names:Array;
			var name:String;
			var i:int;
			if (root is ILinkableDynamicObject)
			{
				object = (root as ILinkableDynamicObject).internalObject;
				internalGetDescendants(output, object, filter, ignoreList, depth);
			}
			else if (root is ILinkableHashMap)
			{
				names = (root as ILinkableHashMap).getNames();
				var objects:Array = (root as ILinkableHashMap).getObjects();
				for (i = 0; i < names.length; i++)
				{
					name = names[i] as String;
					object = objects[i] as ILinkableObject;
					internalGetDescendants(output, object, filter, ignoreList, depth);
				}
			}
			else
			{
				names = getLinkablePropertyNames(root);
				for (i = 0; i < names.length; i++)
				{
					name = names[i] as String;
					object = root[name] as ILinkableObject;
					internalGetDescendants(output, object, filter, ignoreList, depth);
				}
			}
		}

		/**
		 * This function gets a list of sessioned property names so accessor functions for non-sessioned properties do not have to be called.
		 * @param linkableObject An object containing sessioned properties.
		 * @param getDeprecatedNames If this is set to true, deprecated sessioned property names will be returned instead.
		 * @return An Array containing the names of the sessioned properties of that object class.
		 */
		weave_internal function getLinkablePropertyNames(linkableObject:ILinkableObject, getDeprecatedNames:Boolean = false):Array
		{
			if (linkableObject == null)
			{
				var error:Error = new Error("SessionManager.getLinkablePropertyNames(): linkableObject cannot be null.");
				ErrorManager.reportError(error);
				return [];
			}

			var className:String = getQualifiedClassName(linkableObject);
			var propertyNames:Array = classNameToSessionedPropertyNamesMap[className] as Array;
			var deprecatedNames:Array = classNameToDeprecatedSessionedPropertyNamesMap[className] as Array;
			if (propertyNames == null)
			{
				propertyNames = new Array();
				deprecatedNames = new Array();
				// iterate over the public properties, saving the names of the ones that implement ILinkableObject
				var xml:XML = describeType(linkableObject);
				//trace(xml.toXMLString());
				for each (var tags:XMLList in [xml.constant, xml.variable, xml.accessor.(@access != "writeonly")])
				{
					for each (var tag:XML in tags)
					{
						// Only include this property name if it implements ILinkableObject.
						if (ClassUtils.classImplements(tag.attribute("type"), ILinkableObjectQualifiedClassName))
						{
							var propName:String = tag.attribute("name").toString();
							if (tag.metadata.(@name == "Deprecated").length() == 1)
								deprecatedNames.push(propName);
							else
								propertyNames.push(propName);
						}
					}
				}
				deprecatedNames.sort();
				propertyNames.sort();
				// do not save property names if the class is dynamic
				if (xml.attribute("isDynamic").toString() == "false")
				{
					classNameToSessionedPropertyNamesMap[className] = propertyNames;
					classNameToDeprecatedSessionedPropertyNamesMap[className] = deprecatedNames;
				}
			}
			return getDeprecatedNames ? deprecatedNames : propertyNames;
		}
		// qualified class name of ILinkableObject
		internal static const ILinkableObjectQualifiedClassName:String = getQualifiedClassName(ILinkableObject);
		
		/**
		 * This maps a parent ILinkableObject to a Dictionary, which maps each child ILinkableObject it owns to a value of true.
		 */
		private const ownerToChildDictionaryMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a child ILinkableObject to its registered owner.
		 */
		private const childToOwnerMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a child ILinkableObject to a Dictionary, which maps each of its registered parent ILinkableObjects to a value of true.
		 * Example: childToParentDictionaryMap[child][parent] == true
		 */
		private const childToParentDictionaryMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a parent ILinkableObject to a Dictionary, which maps each of its registered child ILinkableObjects to a value of true.
		 * Example: parentToChildDictionaryMap[parent][child] == true
		 */
		private const parentToChildDictionaryMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps an ILinkableObject to a ICallbackCollection associated with it.
		 */
		private const linkableObjectToCallbackCollectionMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly

		/**
		 * This function gets the ICallbackCollection associated with an ILinkableObject.
		 * If there is no ICallbackCollection defined for the object, one will be created.
		 * This ICallbackCollection is used for reporting changes in the session state
		 * @param linkableObject An ILinkableObject to get the associated ICallbackCollection for.
		 * @return The ICallbackCollection associated with the given object.
		 */
		public function getCallbackCollection(linkableObject:ILinkableObject):ICallbackCollection
		{
			if (linkableObject == null)
				return null;
			
			if (linkableObject is ICallbackCollection)
				return linkableObject as ICallbackCollection;
			
			var objectCC:ICallbackCollection = linkableObjectToCallbackCollectionMap[linkableObject] as ICallbackCollection;
			if (objectCC == null)
			{
				objectCC = new CallbackCollection();
				linkableObjectToCallbackCollectionMap[linkableObject] = objectCC;
			}
			return objectCC;
		}

		/**
		 * This function checks if an object has been disposed of by SessionManager.
		 * @param object An object to check.
		 * @return true if SsessionManager.dispose() was called for the specified object.
		 * 
		 */
		public function objectWasDisposed(object:Object):Boolean
		{
			if (object == null)
				return false;
			if (object is ILinkableObject)
			{
				var cc:CallbackCollection = getCallbackCollection(object as ILinkableObject) as CallbackCollection;
				if (cc)
					return cc.wasDisposed;
			}
			return _disposedObjectsMap[object] != undefined;
		}
		
		private const _disposedObjectsMap:Dictionary = new Dictionary(true); // weak keys to be gc-friendly
		
		private static const DISPOSE:String = "dispose"; // this is the name of the dispose() function.

		/**
		 * This function should be called when an ILinkableObject or IDisposableObject is no longer needed.
		 * @param object An ILinkableObject or an IDisposableObject to clean up.
		 * @param moreObjects More objects to clean up.
		 */
		public function disposeObjects(object:Object, ...moreObjects):void
		{
			if (object != null)
			{
				try
				{
					// if the object implements IDisposableObject, call its dispose() function now
					if (object is IDisposableObject)
					{
						(object as IDisposableObject).dispose();
					}
					else if (object.hasOwnProperty(DISPOSE))
					{
						// call dispose() anyway if it exists, because it is common to forget to implement IDisposableObject.
						object[DISPOSE]();
					}
				}
				catch (e:Error)
				{
					ErrorManager.reportError(e);
				}
				
				var linkableObject:ILinkableObject = object as ILinkableObject;
				if (linkableObject)
				{
					// dispose of the callback collection corresponding to the object.
					// this removes all callbacks, including the one that triggers parent callbacks.
					var objectCC:ICallbackCollection = getCallbackCollection(linkableObject);
					if (objectCC != linkableObject)
						disposeObjects(objectCC);
					
					// unregister from parents
					if (childToParentDictionaryMap[linkableObject] != undefined)
					{
						// remove the parent-to-child mappings
						for (var parent:Object in childToParentDictionaryMap[linkableObject])
							if (parentToChildDictionaryMap[parent] != undefined)
								delete parentToChildDictionaryMap[parent][linkableObject];
						// remove child-to-parent mapping
						delete childToParentDictionaryMap[linkableObject];
					}
		
					// unregister from owner
					var owner:ILinkableObject = childToOwnerMap[linkableObject] as ILinkableObject;
					if (owner != null)
					{
						if (ownerToChildDictionaryMap[owner] != undefined)
							delete ownerToChildDictionaryMap[owner][linkableObject];
						delete childToOwnerMap[linkableObject];
					}
		
					// if the object is an ILinkableVariable, unlink it from all bindable properties that were previously linked
					if (linkableObject is ILinkableVariable)
						for (var bindableParent:* in _changeWatcherMap[linkableObject])
							for (var bindablePropertyName:String in _changeWatcherMap[linkableObject][bindableParent])
								unlinkBindableProperty(linkableObject as ILinkableVariable, bindableParent, bindablePropertyName);
					
					// unlink this object from all other linkable objects
					if (linkedObjectsDictionaryMap[linkableObject] != undefined)
						for (var otherObject:Object in linkedObjectsDictionaryMap[linkableObject])
							unlinkSessionState(linkableObject, otherObject as ILinkableObject);
					
					// dispose of all registered children that this object owns
					var children:Dictionary = ownerToChildDictionaryMap[linkableObject] as Dictionary;
					if (children != null)
					{
						// clear the pointers to the child dictionaries for this object
						delete ownerToChildDictionaryMap[linkableObject];
						delete parentToChildDictionaryMap[linkableObject];
						// dispose of the children this object owned
						for (var child:Object in children)
							disposeObjects(child as ILinkableObject);
					}
					
					// FOR DEBUGGING PURPOSES
					if (runningDebugFlashPlayer)
						objectCC.addImmediateCallback(null, debugDisposedObject, [linkableObject, new Error("Object was disposed")]);
				}
				
				var displayObject:DisplayObject = object as DisplayObject;
				if (displayObject)
				{
					// remove this DisplayObject from its parent
					var parentContainer:DisplayObjectContainer = displayObject.parent;
					try
					{
						if (parentContainer && parentContainer.contains(displayObject))
							parentContainer.removeChild(displayObject);
					}
					catch (e:Error)
					{
						// an error may occur if removeChild() is called twice.
					}
					parentContainer = displayObject as DisplayObjectContainer;
					if (parentContainer)
					{
						// Removing all children fixes errors that may occur in the next
						// frame related to callLaterDispatcher and validateDisplayList.
						while (parentContainer.numChildren > 0)
						{
							try {
								parentContainer.removeChildAt(parentContainer.numChildren - 1);
							} catch (e:Error) { }
						}
					}
					if (displayObject is UIComponent)
						(displayObject as UIComponent).mx_internal::cancelAllCallLaters();
				}
			}
			
			_disposedObjectsMap[object] = true;
			
			// dispose of the remaining specified objects
			for (var i:int = 0; i < moreObjects.length; i++)
				disposeObjects(moreObjects[i]);
		}
		
		// FOR DEBUGGING PURPOSES
		private function debugDisposedObject(disposedObject:ILinkableObject, disposedError:Error):void
		{
			// set some variables to aid in debugging
			var obj:* = disposedObject;
			var ownerPath:Array = []; while (obj = getLinkableObjectOwner(obj)) { ownerPath.unshift(obj); }
			var parents:Array = []; for (obj in childToParentDictionaryMap[disposedObject] || []) { parents.push[obj]; }
			var children:Array = []; for (obj in parentToChildDictionaryMap[disposedObject] || []) { children.push[obj]; }
			var sessionState:Object = getSessionState(disposedObject);

			var msg:String = "Disposed object still running callbacks: " + getQualifiedClassName(disposedObject);
			if (disposedObject is ILinkableVariable)
				msg += ' (value = ' + (disposedObject as ILinkableVariable).getSessionState() + ')';
			var error:Error = new Error(msg);
			trace(disposedError.getStackTrace());
			trace(error.getStackTrace());
			ErrorManager.reportError(error);
		}

//		public function getOwnerPath(root:ILinkableObject, descendant:ILinkableObject):Array
//		{
//			var result:Array = [];
//			while (descendant && root != descendant)
//			{
//				var owner:ILinkableObject = getOwner(descendant);
//				if (!owner)
//					break;
//				var name:String = getChildPropertyName(parent as ILinkableObject, descendant);
//			}
//			return result;
//		}
		
		/**
		 * This function is for debugging purposes only.
		 */
		private function getPaths(root:ILinkableObject, descendant:ILinkableObject):Array
		{
			var results:Array = [];
			for (var parent:Object in childToParentDictionaryMap[descendant])
			{
				var name:String;
				if (parent is ILinkableHashMap)
					name = (parent as ILinkableHashMap).getName(descendant);
				else
					name = getChildPropertyName(parent as ILinkableObject, descendant);
				
				if (name != null)
				{
					// this parent may be the one we want
					var result:Array = getPaths(root, parent as ILinkableObject);
					if (result != null)
					{
						result.push(name);
						results.push(result);
					}
				}
			}
			if (results.length == 0)
				return root == null ? results : null;
			return results;
		}

		/**
		 * internal use only
		 */
		private function getChildPropertyName(parent:ILinkableObject, child:ILinkableObject):String
		{
			// find the property name that returns the child
			for each (var name:String in getLinkablePropertyNames(parent))
				if (parent[name] == child)
					return name;
			return null;
		}
		
		/**
		 * internal use only
		 * @param child A sessioned object to return siblings for.
		 * @param filter A Class to filter by (results will only include objects that are of this type).
		 * @return An Array of ILinkableObjects having the same parent of the given child.
		 */
//		private function getSiblings(child:ILinkableObject, filter:Class = null):Array
//		{
//			// if this child has no parents, it has no siblings.
//			if (childToParentDictionaryMap[child] === undefined)
//				return [];
//			
//			var owner:ILinkableObject = getOwner(child);
//			
//			// get all the children of this owner, minus the given child
//			var siblings:Array = [];
//			for (var sibling:Object in ownerToChildDictionaryMap[owner])
//				if (sibling != child && (filter == null || sibling is filter))
//					siblings.push(sibling);
//			return siblings;
//		}
		
		
		
		
		
		/**************************************
		 * linking sessioned objects together
		 **************************************/





		/**
		 * This will link the session state of two ILinkableObjects.
		 * The session state of 'primary' will be copied over to 'secondary' after linking them.
		 * @param primary An ILinkableObject to give authority over the initial shared value.
		 * @param secondary The ILinkableObject to link with 'primary' via session state.
		 */
		public function linkSessionState(primary:ILinkableObject, secondary:ILinkableObject):void
		{
			if (primary == null || secondary == null)
			{
				var error:Error = new Error("SessionManager.linkObjects(): Parameters to this function cannot be null.");
				ErrorManager.reportError(error);
				return;
			}
			
			// prevent
			if (primary == secondary)
			{
				trace(new Error("Warning! Attempt to link session state of an object with itself").getStackTrace());
				return;
			}
			
			if (objectToSetterMap[primary] === undefined)
				objectToSetterMap[primary] = function(source:ILinkableObject):void {
					setSessionState(primary, getSessionState(source), true);
				};
			if (objectToSetterMap[secondary] === undefined)
				objectToSetterMap[secondary] = function(source:ILinkableObject):void {
					setSessionState(secondary, getSessionState(source), true);
				};
			
			var primaryCC:ICallbackCollection = getCallbackCollection(primary);
			var secondaryCC:ICallbackCollection = getCallbackCollection(secondary);
			// when secondary changes, copy from secondary to primary, no callback recursion
			secondaryCC.addImmediateCallback(primary, objectToSetterMap[primary], [secondary]);
			// when primary changes, copy from primary to secondary, no callback recursion
			primaryCC.addImmediateCallback(secondary, objectToSetterMap[secondary], [primary], true); // copy from primary now

			// initialize linkedObjectsDictionaryMap entries if necessary
			if (linkedObjectsDictionaryMap[primary] === undefined)
				linkedObjectsDictionaryMap[primary] = new Dictionary(true);
			if (linkedObjectsDictionaryMap[secondary] === undefined)
				linkedObjectsDictionaryMap[secondary] = new Dictionary(true);
			// remember that these two objects are linked.
			linkedObjectsDictionaryMap[primary][secondary] = true;
			linkedObjectsDictionaryMap[secondary][primary] = true;
		}
		/**
		 * This will unlink the session state of two ILinkableObjects that were previously linked with linkSessionState().
		 * @param first The ILinkableObject to unlink from 'second'
		 * @param second The ILinkableObject to unlink from 'first'
		 */
		public function unlinkSessionState(first:ILinkableObject, second:ILinkableObject):void
		{
			if (first == null || second == null)
			{
				var error:Error = new Error("SessionManager.unlinkObjects(): Parameters to this function cannot be null.");
				ErrorManager.reportError(error);
				return;
			}

			// clear the entries that say these two objects are linked.
			if (linkedObjectsDictionaryMap[first] != undefined)
				delete linkedObjectsDictionaryMap[first][second];
			if (linkedObjectsDictionaryMap[second] != undefined)
				delete linkedObjectsDictionaryMap[second][first];
			
			getCallbackCollection(first).removeCallback(objectToSetterMap[second]);
			getCallbackCollection(second).removeCallback(objectToSetterMap[first]);
		}
		/**
		 * This maps an destination ILinkableObject to a function like:
		 *     function(source:ILinkableObject):void { setSessionState(destination, getSessionState(source), true); }
		 * The purpose of having this mapping is to have a different function pointer for each ILinkableObject so addImmediateCallback()
		 * and removeCallback() can be used to link and unlink overlapping pairs of ILinkableObject objects.
		 */
		private const objectToSetterMap:Dictionary = new Dictionary(true);
		/**
		 * This maps a sessioned object to a Dictionary, which maps a linked sessioned object to a value of true.
		 */
		private const linkedObjectsDictionaryMap:Dictionary = new Dictionary(true);





		/******************************************************
		 * linking sessioned objects with bindable properties
		 ******************************************************/
		
		
		
		
		/**
		 * This function will link the session state of an ILinkableVariable to a bindable property of an object.
		 * Prior to linking, the value of the ILinkableVariable will be copied over to the bindable property.
		 * @param linkableVariable An ILinkableVariable to link to a bindable property.
		 * @param bindableParent An object with a bindable property.
		 * @param bindablePropertyName The variable name of the bindable property.
		 */
		public function linkBindableProperty(linkableVariable:ILinkableVariable, bindableParent:Object, bindablePropertyName:String):void
		{
			var error:Error;
			
			if (linkableVariable == null || bindableParent == null || bindablePropertyName == null)
			{
				error = new Error("SessionManager.linkBindableProperty(): Parameters to this function cannot be null.");
				ErrorManager.reportError(error);
				return;
			}
			
			if (!bindableParent.hasOwnProperty(bindablePropertyName))
			{
				error = new Error('linkBindableProperty(): Unable to access property "'+bindablePropertyName+'" in class '+getQualifiedClassName(bindableParent));
				ErrorManager.reportError(error);
				return;
			}
			
			// copySessionState is a function that takes zero parameters and sets the bindable value.
			var setBindableProperty:Function = function():void
			{
				var value:Object = linkableVariable.getSessionState();
				if (bindableParent[bindablePropertyName] is Number && !(value is Number))
				{
					try {
						linkableVariable.setSessionState(Number(value));
						value = linkableVariable.getSessionState();
					} catch (e:Error) { }
				}
				bindableParent[bindablePropertyName] = value;
			};
			// copy session state over to bindable property now, before calling BindingUtils.bindSetter(),
			// because that will copy from the bindable property to the sessioned property.
			setBindableProperty();
			// when the bindable value changes, set the session state using setLinkableVariable, which takes one parameter.
			var setLinkableVariable:Function = function(value:Object):void
			{
				// unlink if linkableVariable was disposed of
				if (objectWasDisposed(linkableVariable))
					unlinkBindableProperty(linkableVariable, bindableParent, bindablePropertyName);
				else
					linkableVariable.setSessionState(value);
			};
			var watcher:ChangeWatcher = BindingUtils.bindSetter(setLinkableVariable, bindableParent, bindablePropertyName);
			// save a mapping from the linkableVariable,bindableParent,bindablePropertyName parameters to the watcher for the property
			if (_changeWatcherMap[linkableVariable] === undefined)
				_changeWatcherMap[linkableVariable] = new Dictionary(true);
			if (_changeWatcherMap[linkableVariable][bindableParent] === undefined)
				_changeWatcherMap[linkableVariable][bindableParent] = new Object();
			_changeWatcherMap[linkableVariable][bindableParent][bindablePropertyName] = watcher;
			// when session state changes, set bindable property
			_changeWatcherToCopyFunctionMap[watcher] = setBindableProperty;
			getCallbackCollection(linkableVariable).addImmediateCallback(bindableParent, setBindableProperty);
		}
		/**
		 * This function will unlink an ILinkableVariable from a bindable property that has been previously linked with linkBindableProperty().
		 * @param linkableVariable An ILinkableVariable to unlink from a bindable property.
		 * @param bindableParent An object with a bindable property.
		 * @param bindablePropertyName The variable name of the bindable property.
		 */
		public function unlinkBindableProperty(linkableVariable:ILinkableVariable, bindableParent:Object, bindablePropertyName:String):void
		{
			if (linkableVariable == null || bindableParent == null || bindablePropertyName == null)
			{
				var error:Error = new Error("SessionManager.linkBindableProperty(): Parameters to this function cannot be null.");
				ErrorManager.reportError(error);
				return;
			}
			
			try
			{
				var watcher:ChangeWatcher = _changeWatcherMap[linkableVariable][bindableParent][bindablePropertyName];
				var cc:ICallbackCollection = getCallbackCollection(linkableVariable);
				cc.removeCallback(_changeWatcherToCopyFunctionMap[watcher]);
				watcher.unwatch();
				delete _changeWatcherMap[linkableVariable][bindableParent][bindablePropertyName];
			}
			catch (e:Error)
			{
				//trace(SessionManager, getQualifiedClassName(bindableParent), bindablePropertyName, e.getStackTrace());
			}
		}
		/**
		 * This is a multidimensional mapping, such that
		 *     _changeWatcherMap[linkableVariable][bindableParent][bindablePropertyName]
		 * maps to a ChangeWatcher object.
		 */
		private const _changeWatcherMap:Dictionary = new Dictionary(true); // use weak links to be GC-friendly
		/**
		 * This maps a ChangeWatcher object to a function that was added as a callback to the corresponding ILinkableVariable.
		 */
		private const _changeWatcherToCopyFunctionMap:Dictionary = new Dictionary(); // use weak links to be GC-friendly

		/**
		 * This value is true if the user is running the debug version of the flash player.
		 */		
		public static const runningDebugFlashPlayer:Boolean = (new Error()).getStackTrace() != null;
		
		/**
		 * This function computes the diff of two session states.
		 * @param oldState The source session state.
		 * @param newState The destination session state.
		 * @return A patch that generates the destination session state when applied to the source session state, or undefined if the two states are equivalent.
		 */
		public function computeDiff(oldState:Object, newState:Object):*
		{
			var type:String = typeof(oldState); // the type of null is 'object'
			var diffValue:*;

			// special case if types differ
			if (typeof(newState) != type)
				return newState;
			
			if (type == 'xml')
			{
				if ((oldState as XML).toXMLString() != (newState as XML).toXMLString())
					return newState;
				
				return undefined; // no diff
			}
			else if (type == 'number')
			{
				if (isNaN(oldState as Number) && isNaN(newState as Number))
					return undefined; // no diff
				
				if (oldState != newState)
					return newState;
				
				return undefined; // no diff
			}
			else if (oldState === null || newState === null || type != 'object') // other primitive value
			{
				if (oldState !== newState) // no type-casting
					return newState;
				
				return undefined; // no diff
			}
			else if (oldState is Array && newState is Array)
			{
				// create an array of new DynamicState objects for all new names followed by missing old names
				var i:int;
				var typedState:DynamicState;
				var changeDetected:Boolean = false;
				
				// create oldLookup
				var oldNameOrder:Array = new Array(oldState.length);
				var oldLookup:Object = {};
				for (i = 0; i < oldState.length; i++)
				{
					typedState = DynamicState.cast(oldState[i]);
					//TODO: error checking in case typedState is null
					oldLookup[typedState.objectName] = typedState;
					oldNameOrder[i] = typedState.objectName;
				}
				if (oldState.length != newState.length)
					changeDetected = true;
				
				// create new Array with new DynamicState objects
				var result:Array = [];
				for (i = 0; i < newState.length; i++)
				{
					// create a new DynamicState object so we won't be modifying the one from newState
					typedState = DynamicState.cast(newState[i], true);
					var oldTypedState:DynamicState = oldLookup[typedState.objectName] as DynamicState;
					delete oldLookup[typedState.objectName]; // remove it from the lookup because it's already been handled
					
					// If the object specified in newState does not exist in oldState, we don't need to do anything further.
					// If the class is the same as before, then we can save a diff instead of the entire session state.
					// If the class DID change, we can't save only a diff -- we need to keep the entire session state.
					// Replace the sessionState in the new DynamicState object with the diff.
					if (oldTypedState != null && oldTypedState.className == typedState.className)
					{
						diffValue = computeDiff(oldTypedState.sessionState, typedState.sessionState);
						if (diffValue === undefined)
						{
							// Since the class name is the same and the session state is the same,
							// we only need to specify that this name is still present.
							result.push(typedState.objectName);
							
							if (!changeDetected && oldNameOrder[i] != typedState.objectName)
								changeDetected = true;
							
							continue;
						}
						typedState.sessionState = diffValue;
					}
					
					// save in new array and remove from lookup
					result.push(typedState);
					changeDetected = true;
				}
				
				// Anything remaining in the lookup does not appear in newState.
				// Add DynamicState entries with a null className to convey that each of these objects should be removed.
				for (var removedName:String in oldLookup)
				{
					result.push(new DynamicState(removedName, null));
					changeDetected = true;
				}
				
				if (changeDetected)
					return result;
				
				return undefined; // no diff
			}
			else // nested object
			{
				var diff:* = undefined; // start with no diff
				
				// find old properties that changed value
				for (var oldName:String in oldState)
				{
					diffValue = computeDiff(oldState[oldName], newState[oldName]);
					if (diffValue != undefined)
					{
						if (!diff)
							diff = {};
						diff[oldName] = diffValue;
					}
				}

				// find new properties
				for (var newName:String in newState)
				{
					if (oldState[newName] === undefined)
					{
						if (!diff)
							diff = {};
						diff[newName] = newState[newName];
					}
				}

				return diff;
			}
		}
	}
}
