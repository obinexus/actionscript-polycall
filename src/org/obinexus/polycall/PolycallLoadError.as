package org.obinexus.polycall
{
    /**
     * The native library could not be used: reason is "not-found",
     * "missing-symbol" (e.g. an old 1.0 library), "abi-mismatch" or
     * "ffi-unavailable" (koffi missing). Thrown before any call reaches it.
     */
    public class PolycallLoadError extends Error
    {
        public var library:String;
        public var reason:String;

        public function PolycallLoadError(library:String, reason:String, message:String)
        {
            var text:String = "actionscript-polycall: cannot use Polycall library '" + library + "': " + message;
            super(text);
            // Error subclasses compiled to JavaScript do not inherit the message from super()
            this.message = text;
            this.name = "PolycallLoadError";
            this.library = library;
            this.reason = reason;
        }
    }
}
