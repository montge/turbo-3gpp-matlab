classdef System < handle
    % matlab.System Minimal GNU Octave shim for MATLAB's System Object base class.
    %
    % This class lets the existing turbo_coding_chain / turbo_encoding_chain /
    % turbo_decoding_chain classdefs (which declare `< matlab.System`) load and
    % run under GNU Octave 8.4+, which does not ship matlab.System.
    %
    % It implements only the surface area the existing code uses:
    %   - setProperties(obj, nargin, 'Name', Value, ...)
    %   - step(obj, ...) with lazy setupImpl on first call
    %   - reset(obj) -> resetImpl
    %   - release(obj) so the next step re-runs setupImpl
    %   - subsref so obj(arg) dispatches to step(obj, arg)
    %
    % MATLAB users are unaffected: MATLAB resolves matlab.System to its own
    % built-in class when its toolbox is installed; this shim is only picked
    % up under Octave (or under MATLAB without the toolbox).

    properties (Access = private)
        is_setup_done = false;
    end

    methods
        function obj = System()
        end

        function setProperties(obj, n_args, varargin)
            if mod(n_args, 2) ~= 0
                error('matlab:System:setProperties', ...
                      'setProperties expects an even number of Name/Value arguments.');
            end
            for k = 1:2:n_args
                name = varargin{k};
                value = varargin{k + 1};
                if ~ischar(name)
                    error('matlab:System:setProperties', ...
                          'Property name at position %d is not a string.', k);
                end
                obj.(name) = value;
            end
        end

        function varargout = step(obj, varargin)
            if ~obj.is_setup_done
                setupImpl(obj);
                obj.is_setup_done = true;
            end
            n_out = max(1, nargout);
            varargout = cell(1, n_out);
            [varargout{1:n_out}] = stepImpl(obj, varargin{:});
        end

        function reset(obj)
            % Match step()'s lazy-setup semantics. Without this, calling
            % reset(obj) before any step(obj, ...) would dispatch to a
            % subclass resetImpl that may reference properties populated by
            % setupImpl (turbo_decoding_chain.resetImpl reads obj.buffers,
            % which setupImpl allocates).
            if ~obj.is_setup_done
                setupImpl(obj);
                obj.is_setup_done = true;
            end
            resetImpl(obj);
        end

        function release(obj)
            obj.is_setup_done = false;
        end

        function varargout = subsref(obj, S)
            % Implement callable syntax: obj(arg1, arg2, ...) -> step(obj, ...)
            % This matches how the simulation driver invokes hEnc(a) and
            % hDec(f_tilde) without explicitly calling step.
            if numel(S) >= 1 && strcmp(S(1).type, '()')
                args = S(1).subs;
                n_out = max(1, nargout);
                outs = cell(1, n_out);
                [outs{1:n_out}] = step(obj, args{:});
                if numel(S) > 1
                    % Chained indexing like obj(a).field is uncommon here, but
                    % support it by forwarding the remainder.
                    [outs{1:n_out}] = builtin('subsref', outs{1}, S(2:end));
                end
                varargout = outs;
            else
                % Fall back to default dotted/braced behavior.
                n_out = max(1, nargout);
                outs = cell(1, n_out);
                [outs{1:n_out}] = builtin('subsref', obj, S);
                varargout = outs;
            end
        end
    end

    methods (Access = protected)
        function setupImpl(~)
        end

        function processTunedPropertiesImpl(~)
        end

        function resetImpl(~)
        end

        function stepImpl(~, varargin) %#ok<INUSD>
            error('matlab:System:NotImplemented', ...
                  'Subclass must implement stepImpl.');
        end
    end
end
