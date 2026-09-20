//! Ruby binding to the protovalidate-cc engine, exposed as
//! `Protovalidate::Native::Engine`. Only bytes cross the boundary: serialized
//! `FileDescriptorProto`s and messages in, serialized `buf.validate.Violations`
//! out. Everything else, including the error classes, is defined in Ruby.

use magnus::Module as _;
use magnus::Object as _;

/// The engine, shared between Ruby threads. `validate` takes the read lock and
/// `add_file` the write lock, matching the shim's thread-safety contract.
#[magnus::wrap(class = "Protovalidate::Native::Engine", free_immediately)]
struct Engine {
    inner: std::sync::RwLock<protovalidate_cc_sys::Engine>,
}

impl Engine {
    fn new(ruby: &magnus::Ruby) -> Result<Self, magnus::Error> {
        let inner = protovalidate_cc_sys::Engine::new()
            .map_err(|message| crate::protovalidate_error(ruby, "Error", message))?;
        Ok(Self {
            inner: std::sync::RwLock::new(inner),
        })
    }

    /// Adds a serialized `FileDescriptorProto` to the engine's descriptor pool.
    fn add_file(
        ruby: &magnus::Ruby,
        rb_self: &Self,
        file: magnus::RString,
    ) -> Result<(), magnus::Error> {
        // SAFETY: the bytes are copied out before any other Ruby call.
        let bytes = unsafe { file.as_slice() }.to_vec();
        let mut engine = rb_self
            .inner
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        engine
            .add_file(&bytes)
            .map_err(|error| crate::to_ruby_error(ruby, error))
    }

    /// Validates a serialized message of the named type, returning serialized
    /// violations or `nil` when it is valid.
    fn validate(
        ruby: &magnus::Ruby,
        rb_self: &Self,
        type_name: String,
        payload: magnus::RString,
        fail_fast: bool,
    ) -> Result<Option<magnus::RString>, magnus::Error> {
        // SAFETY: the bytes are copied out before any other Ruby call, and the
        // copy is what the GVL-free section reads.
        let payload = unsafe { payload.as_slice() }.to_vec();
        let result = crate::gvl::without_gvl(|| {
            let engine = rb_self
                .inner
                .read()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            engine.validate(&type_name, &payload, fail_fast)
        });
        match result {
            Ok(None) => Ok(None),
            Ok(Some(buffer)) => Ok(Some(ruby.str_from_slice(buffer.as_slice()))),
            Err(error) => Err(crate::to_ruby_error(ruby, error)),
        }
    }
}

/// Maps an engine failure onto the Ruby error hierarchy. The
/// compilation/evaluation split is observable behaviour: the conformance
/// harness buckets results by it.
fn to_ruby_error(ruby: &magnus::Ruby, error: protovalidate_cc_sys::PvError) -> magnus::Error {
    match error {
        protovalidate_cc_sys::PvError::Compilation(message) => {
            crate::protovalidate_error(ruby, "CompilationError", message)
        }
        protovalidate_cc_sys::PvError::Evaluation(message) => {
            crate::protovalidate_error(ruby, "EvaluationError", message)
        }
        protovalidate_cc_sys::PvError::Argument(message) => {
            magnus::Error::new(ruby.exception_arg_error(), message)
        }
        protovalidate_cc_sys::PvError::Unexpected(message) => {
            crate::protovalidate_error(ruby, "Error", message)
        }
        protovalidate_cc_sys::PvError::Unknown(code, message) => {
            crate::protovalidate_error(ruby, "Error", format!("unknown status {code}: {message}"))
        }
    }
}

/// An error of the class `Protovalidate::<name>`, defined by the Ruby side of
/// the gem before this extension is loaded.
fn protovalidate_error(ruby: &magnus::Ruby, name: &str, message: String) -> magnus::Error {
    let class = ruby
        .class_object()
        .const_get::<_, magnus::RModule>("Protovalidate")
        .and_then(|module| module.const_get::<_, magnus::ExceptionClass>(name));
    match class {
        Ok(class) => magnus::Error::new(class, message),
        Err(lookup_error) => lookup_error,
    }
}

mod gvl {
    struct Slot<F, R> {
        func: Option<F>,
        result: Option<std::thread::Result<R>>,
    }

    unsafe extern "C" fn trampoline<F, R>(data: *mut std::ffi::c_void) -> *mut std::ffi::c_void
    where
        F: FnOnce() -> R,
    {
        // SAFETY: `data` is the `Slot` that `without_gvl` keeps alive on its
        // stack for the duration of the call.
        let slot = unsafe { &mut *data.cast::<Slot<F, R>>() };
        let func = slot.func.take().expect("the callback runs once");
        // A panic must not unwind through Ruby's C frames.
        slot.result = Some(std::panic::catch_unwind(std::panic::AssertUnwindSafe(func)));
        std::ptr::null_mut()
    }

    /// Runs `func` with the GVL released. The closure must not touch Ruby.
    pub(crate) fn without_gvl<F, R>(func: F) -> R
    where
        F: FnOnce() -> R,
    {
        let mut slot: Slot<F, R> = Slot {
            func: Some(func),
            result: None,
        };
        // SAFETY: the trampoline reads `slot` only while this frame is live.
        // No unblocking function is registered, so interrupts are delivered
        // once the (short, CPU-bound) validation returns.
        unsafe {
            rb_sys::rb_thread_call_without_gvl(
                Some(trampoline::<F, R>),
                (&raw mut slot).cast::<std::ffi::c_void>(),
                None,
                std::ptr::null_mut(),
            );
        }
        match slot.result.take().expect("the callback ran") {
            Ok(value) => value,
            Err(payload) => std::panic::resume_unwind(payload),
        }
    }
}

#[magnus::init]
fn init(ruby: &magnus::Ruby) -> Result<(), magnus::Error> {
    let module = ruby
        .define_module("Protovalidate")?
        .define_module("Native")?;
    let class = module.define_class("Engine", ruby.class_object())?;
    class.define_singleton_method("new", magnus::function!(Engine::new, 0))?;
    class.define_method("add_file", magnus::method!(Engine::add_file, 1))?;
    class.define_method("validate", magnus::method!(Engine::validate, 3))?;
    Ok(())
}
