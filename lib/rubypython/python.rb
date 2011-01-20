require 'ffi'
require 'open3'

module RubyPython
  #This module provides access to the Python C API functions via the Ruby ffi
  #gem. Documentation for these functions may be found [here](http://docs.python.org/c-api/). Likewise the FFI gem documentation may be found [here](http://rdoc.info/projects/ffi/ffi).
  module Python
    extend FFI::Library

    # This much we can assume works without anything special at all.
    PYTHON_VERSION = Open3.popen3("python --version") { |i,o,e| e.read }.chomp.split[1].to_f
    PYTHON_NAME = "python#{PYTHON_VERSION}"
    LIB_NAME = "#{FFI::Platform::LIBPREFIX}#{PYTHON_NAME}"
    LIB_EXT = FFI::Platform::LIBSUFFIX
    PYTHON_SYS_PREFIX = %x{#{PYTHON_NAME} -c "import sys; print(sys.prefix)"}.chomp

    # Here's where we run into problems, as not everything works quite the
    # way we expect it to.
    #
    # The default libname will be something like libpython2.6.so (or .dylib)
    # or maybe even python2.6.dll on Windows.
    libname = "#{LIB_NAME}.#{LIB_EXT}"

    # We may need to look in multiple locations for Python, so let's build
    # this as an array.
    locations = [ File.join(PYTHON_SYS_PREFIX, "lib", libname) ]

    if FFI::Platform.mac?
      # On the Mac, let's add a special case that has even a different
      # libname. This may not be fully useful on future versions of OS X,
      # but it should work on 10.5 and 10.6. Even if it doesn't, the next
      # step will (/usr/lib/libpython<version>.dylib is a symlink to the
      # correct location).
      locations << File.join(PYTHON_SYS_PREFIX, "Python")
      # Let's also look in the location that was originally set in this
      # library:
      File.join(PYTHON_SYS_PREFIX, "lib", "#{PYTHON_NAME}", "config",
                libname)
    end

    if FFI::Platform.unix?
      # On Unixes, let's look in alternative places, too. Just in case.
      locations << File.join("/opt/local/lib", libname)
      locations << File.join("/opt/lib", libname)
      locations << File.join("/usr/local/lib", libname)
      locations << File.join("/usr/lib", libname)
    end

    # Get rid of redundant locations.
    locations.uniq!

    dyld_flags = FFI::DynamicLibrary::RTLD_LAZY | FFI::DynamicLibrary::RTLD_GLOBAL
    exceptions = []

    locations.each do |location|
      begin
        @ffi_libs = [ FFI::DynamicLibrary.open(location, dyld_flags) ]
        LIB = location
        break
      rescue LoadError => ex
        @ffi_libs = nil
        exceptions << ex
      end
    end

    raise exceptions.first if @ffi_libs.nil?

    #The class is a little bit of a hack to extract the address of global
    #structs. If someone knows a better way please let me know.
    class DummyStruct < FFI::Struct
      layout :dummy_var, :int
    end

    #Python interpreter startup and shutdown
    attach_function :Py_IsInitialized, [], :int
    attach_function :Py_Initialize, [], :void
    attach_function :Py_Finalize, [], :void

    #Module methods
    attach_function :PyImport_ImportModule, [:string], :pointer

    #Object Methods
    attach_function :PyObject_HasAttrString, [:pointer, :string], :int
    attach_function :PyObject_GetAttrString, [:pointer, :string], :pointer
    attach_function :PyObject_SetAttrString, [:pointer, :string, :pointer], :int

    attach_function :PyObject_Compare, [:pointer, :pointer], :int

    attach_function :PyObject_CallObject, [:pointer, :pointer], :pointer
    attach_function :PyCallable_Check, [:pointer], :int

    ###Python To Ruby Conversion
    #String Methods
    attach_function :PyString_AsString, [:pointer], :string
    attach_function :PyString_FromString, [:string], :pointer

    #List Methods
    attach_function :PyList_GetItem, [:pointer, :int], :pointer
    attach_function :PyList_Size, [:pointer], :int
    attach_function :PyList_New, [:int], :pointer
    attach_function :PyList_SetItem, [:pointer, :int, :pointer], :void

    #Integer Methods
    attach_function :PyInt_AsLong, [:pointer], :long
    attach_function :PyInt_FromLong, [:long], :pointer

    attach_function :PyLong_AsLong, [:pointer], :long
    attach_function :PyLong_FromLong, [:pointer], :long

    #Float Methods
    attach_function :PyFloat_AsDouble, [:pointer], :double
    attach_function :PyFloat_FromDouble, [:double], :pointer

    #Tuple Methods
    attach_function :PySequence_List, [:pointer], :pointer
    attach_function :PySequence_Tuple, [:pointer], :pointer
    attach_function :PyTuple_Pack, [:int, :varargs], :pointer

    #Dict/Hash Methods
    attach_function :PyDict_Next, [:pointer, :pointer, :pointer, :pointer], :int
    attach_function :PyDict_New, [], :pointer
    attach_function :PyDict_SetItem, [:pointer, :pointer, :pointer], :int
    attach_function :PyDict_Contains, [:pointer, :pointer], :int
    attach_function :PyDict_GetItem, [:pointer, :pointer], :pointer

    #Function Constants
    METH_VARARGS = 1
    attach_function :PyCFunction_New, [:pointer, :pointer], :pointer
    callback :PyCFunction, [:pointer, :pointer], :pointer

    #Error Methods
    attach_function :PyErr_Fetch, [:pointer, :pointer, :pointer], :void
    attach_function :PyErr_Occurred, [], :pointer
    attach_function :PyErr_Clear, [], :void

    #Reference Counting
    attach_function :Py_IncRef, [:pointer], :void
    attach_function :Py_DecRef, [:pointer], :void

    #Type Objects
    attach_variable :PyString_Type, DummyStruct.by_value
    attach_variable :PyList_Type, DummyStruct.by_value
    attach_variable :PyInt_Type, DummyStruct.by_value
    attach_variable :PyLong_Type, DummyStruct.by_value
    attach_variable :PyFloat_Type, DummyStruct.by_value
    attach_variable :PyTuple_Type, DummyStruct.by_value
    attach_variable :PyDict_Type, DummyStruct.by_value
    attach_variable :PyFunction_Type, DummyStruct.by_value
    attach_variable :PyMethod_Type, DummyStruct.by_value
    attach_variable :PyType_Type, DummyStruct.by_value
    attach_variable :PyClass_Type, DummyStruct.by_value

    attach_variable :Py_TrueStruct, :_Py_TrueStruct, DummyStruct.by_value
    attach_variable :Py_ZeroStruct, :_Py_ZeroStruct, DummyStruct.by_value
    attach_variable :Py_NoneStruct, :_Py_NoneStruct, DummyStruct.by_value

    #This is an implementation of the basic structure of a Python PyObject
    #struct. The C struct is actually much larger, but since we only access
    #the first two data members via FFI and always deal with struct pointers
    #there is no need to mess around with the rest of the object.
    class PyObjectStruct < FFI::Struct
      layout :ob_refcnt, :int,
        :ob_type, :pointer
    end

    #This struct is used when defining Python methods. 
    class PyMethodDef < FFI::Struct
      layout :ml_name, :pointer,
        :ml_meth, :PyCFunction,
        :ml_flags, :int,
        :ml_doc, :pointer
    end

  end
end