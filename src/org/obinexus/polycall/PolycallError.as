package org.obinexus.polycall
{
    /**
     * A failed Polycall call: the C status code (negative POLYCALL_E_*), its
     * name from polycall_strerror() and the detail from polycall_last_error().
     * For call(), `output` holds the remote error object when the runtime
     * answered ({"code":..,"message":..}).
     */
    public class PolycallError extends Error
    {
        public var status:int;
        public var statusName:String;
        public var detail:String;
        public var operation:String;
        public var output:String;

        public function PolycallError(status:int, statusName:String, detail:String, operation:String = null,
                                      output:String = null)
        {
            var text:String = (operation ? operation + ": " : "") + statusName + (detail ? " (" + detail + ")" : "");
            super(text);
            // Error subclasses compiled to JavaScript do not inherit the message from super()
            this.message = text;
            this.name = "PolycallError";
            this.status = status;
            this.statusName = statusName;
            this.detail = detail;
            this.operation = operation;
            this.output = output;
        }

        /** "POLYCALL_E_TIMEOUT" from "POLYCALL_E_TIMEOUT: deadline exceeded" */
        public function get code():String
        {
            var i:int = statusName.indexOf(":");
            return i < 0 ? statusName : statusName.substr(0, i);
        }
    }
}
