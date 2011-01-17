
class DirManager
{
   public static var sIsCygwin = false;
   static var mMade = new Hash<Bool>();

   static public function make(inDir:String)
   {
      var parts = inDir.split("/");
      var total = "";
      for(part in parts)
      {
         if (part!="." && part!="")
         {
            if (total!="") total+="/";
            total += part;
            if (!mMade.exists(total))
            {
               mMade.set(total,true);
               if (!neko.FileSystem.exists(total))
               {
                  neko.Lib.println("mkdir " + total);
                  neko.FileSystem.createDirectory(total);
               }
            }
         }
      }
   }
   static public function deleteRecurse(inDir:String)
   {
      if (neko.FileSystem.exists(inDir))
      {
         var contents = neko.FileSystem.readDirectory(inDir);
         for(item in contents)
         {
            if (item!="." && item!="..")
            {
               var name = inDir + "/" + item;
               if (neko.FileSystem.isDirectory(name))
                  deleteRecurse(name);
               else
                  neko.FileSystem.deleteFile(name);
            }
    }
         neko.FileSystem.deleteDirectory(inDir);
      }
   }

   static public function DosToCygwin(path:String)
   {
      if (sIsCygwin && path.substr(1,1)==":")
         return "/cygdrive/" + path.substr(0,1) + path.substr(2);
      return path;
   }

}

class Compiler
{
   public var mFlags : Array<String>;
   public var mCFlags : Array<String>;
   public var mMMFlags : Array<String>;
   public var mCPPFlags : Array<String>;
   public var mOBJCFlags : Array<String>;
   public var mExe:String;
   public var mOutFlag:String;
   public var mObjDir:String;
   public var mExt:String;

   public var mPCHExt:String;
   public var mPCHCreate:String;
   public var mPCHUse:String;
   public var mPCH:String;

   public var mID:String;

   public function new(inID,inExe:String,inGCCFileTypes)
   {
      mFlags = [];
      mCFlags = [];
      mCPPFlags = [];
      mOBJCFlags = [];
      mMMFlags = [];
      if (inGCCFileTypes)
      {
         mCFlags.push("-x");
         mCFlags.push("c");
         mOBJCFlags.push("-x");
         mOBJCFlags.push("objective-c");
         mMMFlags.push("-x");
         mMMFlags.push("objective-c++");
         mCPPFlags.push("-x");
         mCPPFlags.push("c++");
      }
      mObjDir = "obj";
      mOutFlag = "-o";
      mExe = inExe;
      mID = inID;
      mExt = ".o";
      mPCHExt = ".pch";
      mPCHCreate = "-Yc";
      mPCHUse = "-Yu";
   }

   public function setPCH(inPCH:String)
   {
      mPCH = inPCH;
      if (mPCH=="gcc")
      {
          mPCHExt = ".h.gch";
          mPCHUse = "";
      }
   }

   public function precompile(inHeader:String,inDir:String,inGroup:FileGroup)
   {
      var pch_name = inHeader + mPCHExt;

      var args = inGroup.mCompilerFlags.concat(mFlags).concat( mCPPFlags );

      if (mPCH!="gcc")
      {
         args.push( mPCHCreate + inHeader + ".h" );

         // Create a temp file for including ...
         var tmp_cpp = "__pch.cpp";
         var file = neko.io.File.write(tmp_cpp,false);
         file.writeString("#include <" + inHeader + ".h>\n");
         file.close();

         args.push( tmp_cpp );
         args.push("/Fp" + pch_name);
      }
      else
      {
         args.push( "-o" );
         args.push(pch_name);
         args.push( inDir + "/"  + inHeader + ".h" );
      }


      trace("Creating " + pch_name + ".");
      neko.Lib.println( mExe + " " + args.join(" ") );
      var result = neko.Sys.command( mExe, args );
      if (result!=0)
      {
         if (neko.FileSystem.exists(pch_name))
            neko.FileSystem.deleteFile(pch_name);
         throw "Error creating pch: " + result + " - build cancelled";
      }
   }

   public function compile(inFile:File)
   {
      var path = new neko.io.Path(mObjDir + "/" + inFile.mName);
      var obj_name = path.dir + "/" + path.file + mExt;

      var args = new Array<String>();
      if (inFile.mGroup.mPrecompiledHeader!="")
         args.push("-I.");
      
      args = args.concat(inFile.mCompilerFlags).concat(inFile.mGroup.mCompilerFlags).concat(mFlags);

      var ext = path.ext.toLowerCase();
      if (ext=="c")
         args = args.concat(mCFlags);
      else if (ext=="m")
         args = args.concat(mOBJCFlags);
      else if (ext=="mm")
         args = args.concat(mMMFlags);
      else if (ext=="cpp" || ext=="c++")
         args = args.concat(mCPPFlags);

      if (mPCHUse!="")
         if (inFile.mGroup.mPrecompiledHeader!="")
            args.push(mPCHUse + inFile.mGroup.mPrecompiledHeader + ".h");

      
      args.push( (new neko.io.Path( DirManager.DosToCygwin(inFile.mDir) + inFile.mName)).toString() );

      var out = mOutFlag;
      if (out.substr(-1)==" ")
      {
         args.push(out.substr(0,out.length-1));
         out = "";
      }
      args.push(out + obj_name);
      neko.Lib.println( mExe + " " + args.join(" ") );
      var result = neko.Sys.command( mExe, args );
      if (result!=0)
      {
         if (neko.FileSystem.exists(obj_name))
            neko.FileSystem.deleteFile(obj_name);
         throw "Error : " + result + " - build cancelled";
      }
      return obj_name;
   }
}


class Linker
{
   public var mExe:String;
   public var mFlags : Array<String>;
   public var mOutFlag:String;
   public var mExt:String;
   public var mNamePrefix:String;
   public var mLibDir:String;
   public var mRanLib:String;
   public var mFromFile:String;
   public var mLibs:Array<String>;

   public function new(inExe:String)
   {
      mFlags = [];
      mOutFlag = "-o";
      mExe = inExe;
      mNamePrefix = "";
      mLibDir = "";
      mRanLib = "";
      // Default to on...
      mFromFile = "@";
      mLibs = [];
   }
   public function link(inTarget:Target,inObjs:Array<String>)
   {
      var ext = inTarget.mExt=="" ? mExt : inTarget.mExt;
      var file_name = mNamePrefix + inTarget.mOutput + ext;
      var out_name = inTarget.mOutputDir + file_name;
      if (isOutOfDate(out_name,inObjs) || isOutOfDate(out_name,inTarget.mDepends))
      {
         var args = new Array<String>();
         var out = mOutFlag;
         if (out.substr(-1)==" ")
         {
            args.push(out.substr(0,out.length-1));
            out = "";
         }
         // Build in temp dir, and then move out so all the crap windows
         //  creates stays out of the way
         if (mLibDir!="")
         {
            DirManager.make(mLibDir);
            args.push(out + mLibDir + "/" + file_name);
         }
         else
            args.push(out + out_name);

          args = args.concat(mFlags).concat(inTarget.mFlags);

         // Place list of obj files in a file called "all_objs"
         if (mFromFile=="@")
         {
            var fname = "all_objs";
            var fout = neko.io.File.write(fname,false);
            for(obj in inObjs)
               fout.writeString(obj + "\n");
            fout.close();
            args.push("@" + fname );
         }
         else
            args = args.concat(inObjs);

         args = args.concat(inTarget.mLibs);
         args = args.concat(mLibs);

         neko.Lib.println( mExe + " " + args.join(" ") );
         var result = neko.Sys.command( mExe, args );
         if (result!=0)
            throw "Error : " + result + " - build cancelled";

         if (mRanLib!="")
         {
            args = [out_name];
            neko.Lib.println( mRanLib + " " + args.join(" ") );
            var result = neko.Sys.command( mRanLib, args );
            if (result!=0)
               throw "Error : " + result + " - build cancelled";
         }

         if (mLibDir!="")
         {
            neko.io.File.copy( mLibDir+"/"+file_name, out_name );
            neko.FileSystem.deleteFile( mLibDir+"/"+file_name );
         }
         return  out_name;
      }

      return "";
   }
   function isOutOfDate(inName:String, inObjs:Array<String>)
   {
      if (!neko.FileSystem.exists(inName))
         return true;
      var stamp = neko.FileSystem.stat(inName).mtime.getTime();
      for(obj in inObjs)
      {
         if (!neko.FileSystem.exists(obj))
            throw "Could not find " + obj + " required by " + inName;
         var obj_stamp =  neko.FileSystem.stat(obj).mtime.getTime();
         if (obj_stamp > stamp)
            return true;
      }
      return false;
   }
}



class Stripper
{
   public var mExe:String;
   public var mFlags : Array<String>;

   public function new(inExe:String)
   {
      mFlags = [];
      mExe = inExe;
   }
   public function strip(inTarget:String)
   {
      var args = new Array<String>();

      args = args.concat(mFlags);

      args.push(inTarget);

      neko.Lib.println( mExe + " " + args.join(" ") );
      var result = neko.Sys.command( mExe, args );
      if (result!=0)
         throw "Error : " + result + " - build cancelled";
   }
}

class File
{
   public function new(inName:String, inGroup:FileGroup)
   {
      mName = inName;
      mDir = inGroup.mDir;
      if (mDir!="") mDir += "/";
      // Do not take copy - use reference so it can be updated
      mGroup = inGroup;
      mDepends = [];
      mCompilerFlags = [];
   }
   public function isOutOfDate(inObj:String)
   {
      if (!neko.FileSystem.exists(inObj))
         return true;
      var obj_stamp = neko.FileSystem.stat(inObj).mtime.getTime();
      if (mGroup.isOutOfDate(obj_stamp))
         return true;

      var source_name = mDir+mName;
      if (!neko.FileSystem.exists(source_name))
         throw "Could not find source '" + source_name + "'";
      var source_stamp = neko.FileSystem.stat(source_name).mtime.getTime();
      if (obj_stamp < source_stamp)
         return true;
      for(depend in mDepends)
      {
         if (!neko.FileSystem.exists(depend))
            throw "Could not find dependency '" + depend + "' for '" + mName + "'";
         if (neko.FileSystem.stat(depend).mtime.getTime() > obj_stamp )
            return true;
      }
      return false;
   }
   public var mName:String;
   public var mDir:String;
   public var mDepends:Array<String>;
   public var mCompilerFlags:Array<String>;
   public var mGroup:FileGroup;
}

class FileGroup
{
   public function new(inDir:String)
   {
      mNewest = 0;
      mFiles = [];
      mCompilerFlags = [];
      mPrecompiledHeader = "";
      mMissingDepends = [];
      mDir = inDir;
   }

   public function addDepend(inFile:String)
   {
      if (!neko.FileSystem.exists(inFile))
      {
         mMissingDepends.push(inFile);
         return;
      }
      var stamp =  neko.FileSystem.stat(inFile).mtime.getTime();
      if (stamp>mNewest)
         mNewest = stamp;
   }
   public function checkDependsExist()
   {
      if (mMissingDepends.length>0)
         throw "Could not find dependencies: " + mMissingDepends.join(",");
   }

   public function addCompilerFlag(inFlag:String)
   {
      mCompilerFlags.push(inFlag);
   }

   public function isOutOfDate(inStamp:Float)
   {
      return inStamp<mNewest;
   }

   public function setPrecompiled(inFile:String, inDir:String)
   {
      mPrecompiledHeader = inFile;
      mPrecompiledHeaderDir = inDir;
   }


   public var mNewest:Float;
   public var mCompilerFlags:Array<String>;
   public var mMissingDepends:Array<String>;
   public var mPrecompiledHeader:String;
   public var mPrecompiledHeaderDir:String;
   public var mFiles: Array<File>;
   public var mDir : String;
}


typedef FileGroups = Hash<FileGroup>;

class Target
{
   public function new(inOutput:String, inTool:String,inToolID:String)
   {
      mOutput = inOutput;
      mOutputDir = "";
      mToolID = inToolID;
      mTool = inTool;
      mFiles = [];
      mDepends = [];
      mLibs = [];
      mFlags = [];
      mExt = "";
      mSubTargets = [];
      mFileGroups = [];
      mFlags = [];
      mErrors=[];
      mDirs=[];
   }
   public function addFiles(inGroup:FileGroup)
   {
      mFiles = mFiles.concat(inGroup.mFiles);
      mFileGroups.push(inGroup);
   }
   public function addError(inError:String)
   {
      mErrors.push(inError);
   }
   public function checkError()
   {
       if (mErrors.length>0)
          throw mErrors.join("/");
   }
   public function clean()
   {
      for(dir in mDirs)
      {
         neko.Lib.println("Remove " + dir + "...");
         DirManager.deleteRecurse(dir);
      }
   }

   public var mOutput:String;
   public var mOutputDir:String;
   public var mTool:String;
   public var mToolID:String;
   public var mFiles:Array<File>;
   public var mFileGroups:Array<FileGroup>;
   public var mDepends:Array<String>;
   public var mSubTargets:Array<String>;
   public var mLibs:Array<String>;
   public var mFlags:Array<String>;
   public var mErrors:Array<String>;
   public var mDirs:Array<String>;
   public var mExt:String;
}

typedef Targets = Hash<Target>;
typedef Linkers = Hash<Linker>;

class BuildTool
{
   var mDefines : Hash<String>;
   var mIncludePath:Array<String>;
   var mCompiler : Compiler;
   var mStripper : Stripper;
   var mLinkers : Linkers;
   var mFileGroups : FileGroups;
   var mTargets : Targets;
   static var sAllowNumProcs = true;


   public function new(inMakefile:String,inDefines:Hash<String>,inTargets:Array<String>,
        inIncludePath:Array<String> )
   {
      mDefines = inDefines;
      mFileGroups = new FileGroups();
      mCompiler = null;
      mStripper = null;
      mTargets = new Targets();
      mLinkers = new Linkers();
      mIncludePath = inIncludePath;
      var make_contents = neko.io.File.getContent(inMakefile);
      var xml_slow = Xml.parse(make_contents);
      var xml = new haxe.xml.Fast(xml_slow.firstElement());

      parseXML(xml,"");

      if (mTargets.exists("default"))
         buildTarget("default");
      else
         for(target in inTargets)
            buildTarget(target);
   }


   function findIncludeFile(inBase:String) : String
   {
      if (inBase=="") return "";
     var c0 = inBase.substr(0,1);
     if (c0!="/" && c0!="\\")
     {
        var c1 = inBase.substr(1,1);
        if (c1!=":")
        {
           for(p in mIncludePath)
           {
              var name = p + "/" + inBase;
              if (neko.FileSystem.exists(name))
                 return name;
           }
           return "";
        }
     }
     if (neko.FileSystem.exists(inBase))
        return inBase;
      return "";
   }

   function parseXML(inXML:haxe.xml.Fast,inSection :String)
   {
      for(el in inXML.elements)
      {
         if (valid(el,inSection))
         {
            switch(el.name)
            {
                case "set" : 
                   var name = el.att.name;
                   var value = substitute(el.att.value);
                   mDefines.set(name,value);
                case "setenv" : 
                   var name = el.att.name;
                   var value = substitute(el.att.value);
                   mDefines.set(name,value);
                   neko.Sys.putEnv(name,value);
                case "error" : 
                   var error = substitute(el.att.value);
                   throw(error);
                case "path" : 
                   var path = substitute(el.att.name);
                   var os = neko.Sys.systemName();
                   var sep = (new EReg("window","i")).match(os) ? ";" : ":";
                   neko.Sys.putEnv("PATH", path + sep + neko.Sys.getEnv("PATH"));
                case "compiler" : 
                   mCompiler = createCompiler(el,mCompiler);

                case "stripper" : 
                   mStripper = createStripper(el,mStripper);

                case "linker" : 
                   if (mLinkers.exists(el.att.id))
                      createLinker(el,mLinkers.get(el.att.id));
                   else
                      mLinkers.set( el.att.id, createLinker(el,null) );

                case "files" : 
                   var name = el.att.id;
                   if (mFileGroups.exists(name))
                      createFileGroup(el, mFileGroups.get(name));
                   else
                      mFileGroups.set(name,createFileGroup(el,null));

                case "include" : 
                   var name = substitute(el.att.name);
                   var full_name = findIncludeFile(name);
                   if (full_name!="")
                   {
                      var make_contents = neko.io.File.getContent(full_name);
                      var xml_slow = Xml.parse(make_contents);
                      var section = el.has.section ? el.att.section : "";

                      parseXML(new haxe.xml.Fast(xml_slow.firstElement()),section);
                   }
                   else if (!el.has.noerror)
                   {
                      throw "Could not find include file " + name;
                   }
                case "target" : 
                   var name = el.att.id;
                   mTargets.set(name,createTarget(el));
                case "section" : 
                   parseXML(el,"");
            }
         }
      }
   }


   public function buildTarget(inTarget:String)
   {
      // neko.Lib.println("Build : " + inTarget );
      if (!mTargets.exists(inTarget))
         throw "Could not find target '" + inTarget + "' to build.";
      if (mCompiler==null)
         throw "No compiler defined";

      var target = mTargets.get(inTarget);
      target.checkError();


      for(sub in target.mSubTargets)
         buildTarget(sub);
 
      var thread_var = neko.Sys.getEnv("HXCPP_COMPILE_THREADS");
      // Don't do this by default
      if (thread_var==null && sAllowNumProcs)
         thread_var = neko.Sys.getEnv("NUMBER_OF_PROCESSORS");
      var threads =  (thread_var==null || Std.parseInt(thread_var)<2) ? 1 :
         Std.parseInt(thread_var);


      var objs = new Array<String>();

      for(group in target.mFileGroups)
      {
         group.checkDependsExist();
         var to_be_compiled = new Array<File>();

         for(file in group.mFiles)
         {
            var path = new neko.io.Path(mCompiler.mObjDir + "/" + file.mName);
            var obj_name = path.dir + "/" + path.file + mCompiler.mExt;
            DirManager.make(path.dir);
            objs.push(obj_name);
            if (file.isOutOfDate(obj_name))
               to_be_compiled.push(file);
         }

         if (to_be_compiled.length>0 && group.mPrecompiledHeader!="")
            mCompiler.precompile(group.mPrecompiledHeader, group.mPrecompiledHeaderDir,group);

         if (threads<2)
         {
            for(file in to_be_compiled)
               mCompiler.compile(file);
         }
         else
         {
            var mutex = new neko.vm.Mutex();
            var main_thread = neko.vm.Thread.current();
            var compiler = mCompiler;
            for(t in 0...threads)
            {
               neko.vm.Thread.create(function()
               {
                  try
                  {
                  while(true)
                  {
                     mutex.acquire();
                     if (to_be_compiled.length==0)
                     {
                        mutex.release();
                        break;
                     }
                     var file = to_be_compiled.shift();
                     mutex.release();

                     compiler.compile(file);
                  }
                  } catch (error:Dynamic)
                  {
                     main_thread.sendMessage("Error");
                  }
                  main_thread.sendMessage("Done");
               });
            }

            // Wait for theads to finish...
            for(t in 0...threads)
            {
              var result = neko.vm.Thread.readMessage(true);
              if (result=="Error")
                    throw "Error in building thread";
            }
         }
      }

      switch(target.mTool)
      {
         case "linker":
            if (!mLinkers.exists(target.mToolID))
               throw "Missing linker :\"" + target.mToolID + "\"";

            var exe = mLinkers.get(target.mToolID).link(target,objs);
            if (exe!="" && mStripper!=null)
               if (target.mToolID=="exe" || target.mToolID=="dll")
                  mStripper.strip(exe);

         case "clean":
            target.clean();
      }
   }

   public function createCompiler(inXML:haxe.xml.Fast,inBase:Compiler) : Compiler
   {
      var c = inBase;
      if (inBase==null || inXML.has.replace)
      {
         c = new Compiler(inXML.att.id,inXML.att.exe,mDefines.exists("USE_GCC_FILETYPES"));
         if (mDefines.exists("USE_PRECOMPILED_HEADERS"))
            c.setPCH(mDefines.get("USE_PRECOMPILED_HEADERS"));
      }

      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "flag" : c.mFlags.push(substitute(el.att.value));
                case "cflag" : c.mCFlags.push(substitute(el.att.value));
                case "cppflag" : c.mCPPFlags.push(substitute(el.att.value));
                case "objcflag" : c.mOBJCFlags.push(substitute(el.att.value));
                case "mmflag" : c.mMMFlags.push(substitute(el.att.value));
                case "objdir" : c.mObjDir = substitute((el.att.value));
                case "outflag" : c.mOutFlag = substitute((el.att.value));
                case "exe" : c.mExe = substitute((el.att.name));
                case "ext" : c.mExt = substitute((el.att.value));
                case "pch" : c.setPCH( substitute((el.att.value)) );
            }
      }

      return c;
   }

   public function createStripper(inXML:haxe.xml.Fast,inBase:Stripper) : Stripper
   {
      var s = (inBase!=null && !inXML.has.replace) ? inBase :
                 new Stripper(inXML.att.exe);
      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "flag" : s.mFlags.push(substitute(el.att.value));
                case "exe" : s.mExe = substitute((el.att.name));
            }
      }

      return s;
   }



   public function createLinker(inXML:haxe.xml.Fast,inBase:Linker) : Linker
   {
      var l = (inBase!=null && !inXML.has.replace) ? inBase : new Linker(inXML.att.exe);
      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "flag" : l.mFlags.push(substitute(el.att.value));
                case "ext" : l.mExt = (substitute(el.att.value));
                case "outflag" : l.mOutFlag = (substitute(el.att.value));
                case "libdir" : l.mLibDir = (substitute(el.att.name));
                case "lib" : l.mLibs.push( substitute(el.att.name) );
                case "prefix" : l.mNamePrefix = substitute(el.att.value);
                case "ranlib" : l.mRanLib = (substitute(el.att.name));
                case "fromfile" : l.mFromFile = (substitute(el.att.value));
                case "exe" : l.mExe = (substitute(el.att.name));
            }
      }

      return l;
   }

   public function createFileGroup(inXML:haxe.xml.Fast,inFiles:FileGroup) : FileGroup
   {
      var dir = inXML.has.dir ? substitute(inXML.att.dir) : ".";
      var group = inFiles==null ? new FileGroup(dir) : inFiles;
      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "file" :
                   var file = new File(substitute(el.att.name),group);
                   for(f in el.elements)
                      if (valid(f,"") && f.name=="depend")
                         file.mDepends.push( f.att.name );
                   group.mFiles.push( file );
                case "depend" : group.addDepend( substitute(el.att.name) );
                case "compilerflag" : group.addCompilerFlag( substitute(el.att.value) );
                case "compilervalue" : group.addCompilerFlag( substitute(el.att.name) );
                                       group.addCompilerFlag( substitute(el.att.value) );
                case "precompiledheader" : group.setPrecompiled( substitute(el.att.name),
                          substitute(el.att.dir) );
            }
      }

      return group;
   }


   public function createTarget(inXML:haxe.xml.Fast) : Target
   {
      var output = inXML.has.output ? substitute(inXML.att.output) : "";
      var tool = inXML.has.tool ? inXML.att.tool : "";
      var toolid = inXML.has.toolid ? substitute(inXML.att.toolid) : "";
      var target = new Target(output,tool,toolid);
      for(el in inXML.elements)
      {
         if (valid(el,""))
            switch(el.name)
            {
                case "target" : target.mSubTargets.push( substitute(el.att.id) );
                case "lib" : target.mLibs.push( substitute(el.att.name) );
                case "flag" : target.mFlags.push( substitute(el.att.value) );
                case "depend" : target.mDepends.push( substitute(el.att.name) );
                case "vflag" : target.mFlags.push( substitute(el.att.name) );
                               target.mFlags.push( substitute(el.att.value) );
                case "dir" : target.mDirs.push( substitute(el.att.name) );
                case "outdir" : target.mOutputDir = substitute(el.att.name)+"/";
                case "ext" : target.mExt = (substitute(el.att.value));
                case "files" : var id = el.att.id;
                   if (!mFileGroups.exists(id))
                      target.addError( "Could not find filegroup " + id ); 
                   else
                      target.addFiles( mFileGroups.get(id) );
            }
      }

      return target;
   }


   public function valid(inEl:haxe.xml.Fast,inSection:String) : Bool
   {
      if (inEl.x.get("if")!=null)
         if (!defined(inEl.x.get("if"))) return false;

      if (inEl.has.unless)
         if (defined(inEl.att.unless)) return false;

      if (inSection!="")
      {
         if (inEl.name!="section")
            return false;
         if (!inEl.has.id)
            return false;
         if (inEl.att.id!=inSection)
            return false;
      }

      return true;
   }

   public function defined(inString:String) : Bool
   {
      return mDefines.exists(inString);
   }
   
   static var mVarMatch = new EReg("\\${(.*?)}","");
   public function substitute(str:String) : String
   {
      while( mVarMatch.match(str) )
      {
         var sub = mDefines.get( mVarMatch.matched(1) );
         if (sub==null) sub="";
         str = mVarMatch.matchedLeft() + sub + mVarMatch.matchedRight();
      }

      return str;
   }
   
   
   // Process args and environment.
   static public function main()
   {
      var targets = new Array<String>();
      var defines = new Hash<String>();
      var include_path = new Array<String>();
      var makefile:String="";

      include_path.push(".");

      var args = neko.Sys.args();
      var HXCPP = "";
      // Check for calling from haxelib ...
      if (args.length>0)
      {
         var last:String = (new neko.io.Path(args[args.length-1])).toString();
         var slash = last.substr(-1);
         if (slash=="/"|| slash=="\\") 
            last = last.substr(0,last.length-1);
         if (neko.FileSystem.exists(last) && neko.FileSystem.isDirectory(last))
         {
            // When called from haxelib, the last arg is the original directory, and
            //  the current direcory is the library directory.
            HXCPP = neko.Sys.getCwd();
            defines.set("HXCPP",HXCPP);
            args.pop();
            neko.Sys.setCwd(last);
         }
      }
   
      var os = neko.Sys.systemName();

      for(arg in args)
      {
         if (arg.substr(0,2)=="-D")
            defines.set(arg.substr(2),"");
         if (arg.substr(0,2)=="-I")
            include_path.push(arg.substr(2));
         else if (makefile.length==0)
            makefile = arg;
         else
            targets.push(arg);
      }

      include_path.push(".");
      var env = neko.Sys.environment();
      if (env.exists("HOME"))
        include_path.push(env.get("HOME"));
      if (env.exists("USERPROFILE"))
        include_path.push(env.get("USERPROFILE"));
      include_path.push(HXCPP + "/build-tool");

      var m64 = defines.exists("HXCPP_M64");

      if (defines.exists("iphoneos"))
      {
         defines.set("iphone","iphone");
         defines.set("toolchain","iphoneos");
         defines.set("apple","apple");
         defines.set("BINDIR","iPhone");
      }
      else if (defines.exists("iphonesim"))
      {
         defines.set("toolchain","iphonesim");
         defines.set("iphone","iphone");
         defines.set("apple","apple");
         defines.set("BINDIR","iPhone");
      }
      else if (defines.exists("android"))
      {
         defines.set("toolchain","android");
         defines.set("android","android");
         defines.set("BINDIR","Android");
         if ( (new EReg("mac","i")).match(os) )
            defines.set("ANDROID_HOST","darwin-x86");
         else if ( (new EReg("window","i")).match(os) )
            defines.set("ANDROID_HOST","windows");
         else
            throw "Unknown android host:" + os;
      }
      else if (defines.exists("webos"))
      {
         defines.set("toolchain","webos");
         defines.set("webos","webos");
         defines.set("BINDIR","webOS");
      }
      else if (defines.exists("gph"))
      {
         defines.set("toolchain","gph");
         defines.set("gph","gph");
         defines.set("BINDIR","GPH");
      }
      else if (defines.exists("mingw"))
      {
         defines.set("toolchain","mingw");
         defines.set("mingw","mingw");
         defines.set("BINDIR",m64 ? "Windows64":"Windows");
      }
      else if ( (new EReg("window","i")).match(os) )
      {
         defines.set("toolchain","msvc");
         defines.set("windows","windows");
         defines.set("BINDIR",m64 ? "Windows64":"Windows");

         try
         {
            var proc = new neko.io.Process("cl.exe",[]);
            var str = proc.stderr.readLine();
            proc.close();
            if (str>"")
            {
                var reg = ~/Version\s+(\d+)/i;
                if (reg.match(str))
                   BuildTool.sAllowNumProcs = Std.parseInt(reg.matched(1)) >= 14;
            }
         }
         catch(e:Dynamic){}
      }
      else if ( (new EReg("linux","i")).match(os) )
      {
         defines.set("toolchain","linux");
         defines.set("linux","linux");
         defines.set("BINDIR", m64 ? "Linux64":"Linux");
      }
      else if ( (new EReg("mac","i")).match(os) )
      {
         defines.set("toolchain","mac");
         defines.set("macos","macos");
         defines.set("apple","apple");
         defines.set("BINDIR",m64 ? "Mac64":"Mac64");
      }

      if (targets.length==0)
         targets.push("default");
   
      if (makefile=="")
      {
         neko.Lib.println("Usage :  BuildTool makefile.xml [-DFLAG1] ...  [-DFLAGN] ... [target1]...[targetN]");
      }
      else
      {
         for(e in env.keys())
            defines.set(e, neko.Sys.getEnv(e) );

         if (defines.exists("HXCPP_CONFIG") )
            defines.set("HXCPP_CONFIG",".hxcpp_config.xml");

         if (defines.exists("mingw") && !defines.exists("MINGW_ROOT") )
            defines.set("MINGW_ROOT","c:/MinGW");

         if (defines.exists("android") )
         {
            if (!defines.exists("ANDROID_NDK_ROOT"))
               throw("Please define ANDROID_NDK_ROOT");
            DirManager.sIsCygwin = true;
            defines.set("ANDROID_NDK_ROOT_CYG", DirManager.DosToCygwin(defines.get("ANDROID_NDK_ROOT") ) );
            defines.set( "HXCPP_CYG", DirManager.DosToCygwin(defines.get("HXCPP") ) );
         }

         new BuildTool(makefile,defines,targets,include_path);
      }
   }
   
}
