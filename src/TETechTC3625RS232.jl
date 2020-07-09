module TETechTC3625RS232

using LibSerialPort

const STX = "*"
const ETX = "\r"
const ACK = "^"
const ADDRESS = "00"

"""
    config_TE_port(port_name)

    This function configures the serial port for communication with the controller
"""
function configure_port(name)
    port = sp_get_port_by_name(name)
    sp_open(port, SP_MODE_READ_WRITE)
    config = sp_get_config(port)
    sp_set_config_baudrate(config, 9600)
    sp_set_config_parity(config, SP_PARITY_NONE)
    sp_set_config_bits(config, 8)
    sp_set_config_stopbits(config, 1)
    sp_set_config_rts(config, SP_RTS_OFF)
    sp_set_config_cts(config, SP_CTS_IGNORE)
    sp_set_config_dtr(config, SP_DTR_OFF)
    sp_set_config_dsr(config, SP_DSR_IGNORE)
    sp_set_config(port, config)

    return port
end

"""
    checksum(CMD)

    This function computes the checksum of an input/output command of the controller
"""
function checksum(CMD)
    hex = map(i -> convert(UInt8, CMD[i]), 1:length(CMD))
    decimal = map(i -> convert(Int64, hex[i]), 1:length(hex))
    eight_bit_checksum = sum(decimal)
    hex_for_last_two_digit = string(eight_bit_checksum, base = 16)
    two_of = hex_for_last_two_digit[end-1:end]
end


"""
    twocomp(x)

    This function computes the two complement of a 32 bit number
"""
twocomp(x) = (2^32 - x) * (-1)


"""
    write_controller(port, STRING)

    Generic function that sends a command STRING to the controller attached to port.
    The function tests for errors. If no error it returns the controller response string.
"""
function write_controller(port, STRING)
    sp_flush(port, SPBuffer(3))
    CMD = ADDRESS * STRING
    CHECKSUM = checksum(CMD)
    SEND = STX * CMD * CHECKSUM * ETX
    sp_nonblocking_write(port, SEND) #read the sensor
    sleep(0.06)
    nbytes_read, bytes = sp_nonblocking_read(port, 12)
    sendback = String(bytes)
    if string(sendback[end]) != ACK
        println("Controller did not acknowledge, is it on and plugged in?")
        return nothing
    elseif checksum(sendback[2:end-3]) != sendback[end-2:end-1]
        println("Checksum error")
        return nothing
    else
        return sendback[2:end-3]
    end
end

"""
    decode_temperature(str)

    This function decodes the return string from the controller and returns the temperature in Celsius
"""
function decode_temperature(str, sign)
    dec = try
        parse(Int64, str, base = 16)
    catch
        return missing
    end

    return (sign == :+) ? dec / 100 : twocomp(dec) / 100
end


"""
    set_temperature(st, port)

    Writes the setpoint temperature to the controller. Returns setpoint 
    reported by the controller or nothing if not successful
"""
function set_temperature(port, value)
    sign = (value > 0) ? :+ : :-
    if sign == :+
        step1 = convert(Int64, floor(value * 100[1]))
        step2 = string(step1, base = 16)
        cmd = "1c" * lpad(step2, 8, "0")
    else
        step1 = convert(Int64, floor(value * 100[1]))
        step2 = (sign == :+) ? step1 : convert(Int64, (2^32) + step1[1])
        step3 = string(step2, base = 16)
        cmd = "1c" * step3
    end

    str = write_controller(port, cmd)
    if ~isnothing(str)
        return decode_temperature(str, sign)
    else
        return nothing
    end
end


"""
    read_TE_sensor_T1(port)

    This function reads INPUT1 from the controller
"""
function read_sensor_T1(port)
    str = write_controller(port, "0100000000")
    if ~isnothing(str)
        sign = (str[1:2] == "ff") ? :- : :+
        return decode_temperature(str, sign)
    else
        return missing
    end
end

"""
    read_TE_sensor_T2(port)

    This function reads INPUT2 from the controller
"""
function read_sensor_T2(port)
    str = write_controller(port, "0600000000")
    if ~isnothing(str)
        sign = (str[1:2] == "ff") ? :- : :+
        return decode_temperature(str, sign)
    else
        return missing
    end
end

"""
    turn_power_on(port)

    This function enables power from controller to TE element
"""
function turn_power_on(port)
    cmd = "2d"
    str = "00000001"
    ret = write_controller(port, cmd * str)
end

"""
    turn_power_on(port)

    This function disables power from controller to TE element
"""
function turn_power_off(port)
    cmd = "2d"
    str = "00000000"
    ret = write_controller(port, cmd * str)
end

"""
    read_sensor_type(port)

    This function reports the thermistor type
        0: TS141 5K
        1: TS67 OR TS136 15K
        2: TS91 10K
        3: TS165 230K
        4: TS104 50K
        5: YSI H TP53 10K
"""
function read_sensor_type(port)
    cmd = "43"
    str = "00000000"
    ret = write_controller(port, cmd * str)
end

"""
    set_sensor_type(port, value)

    This function sets the thermistor type to value (integer)
        0: TS141 5K
        1: TS67 OR TS136 15K
        2: TS91 10K
        3: TS165 230K
        4: TS104 50K
        5: YSI H TP53 10K
"""
function set_sensor_type(port, value)
    cmd = "2a"
    str = "0000000" * string(value)
    ret = write_controller(port, cmd * str)
end

"""
    read_proportional_bandwidth(port)

    Fixed-point temperature bandwidth distributed around the control setting 
    in ºF/ºC.  A value of 5 ºF/ºC for bandwidth and control setting of 25 ºF/ºC
     would place the proportional band from 20 ºF/ºC to 30 ºF/ºC; that is, 
     5 ° above and 5 ° below set point.
"""
function read_proportional_bandwidth(port)
    cmd = "51"
    str = "00000000"
    str = write_controller(port, cmd * str)
    if ~isnothing(str)
        sign = (str[1:2] == "ff") ? :- : :+
        return decode_temperature(str, sign)
    else
        return missing
    end
end

"""
    write_proportional_bandwidth(port, value)

    Fixed-point temperature bandwidth distributed around the control setting 
    in ºF/ºC.  A value of 5 ºF/ºC for bandwidth and control setting of 25 ºF/ºC
     would place the proportional band from 20 ºF/ºC to 30 ºF/ºC; that is, 
     5 ° above and 5 ° below set point.
"""
function write_proportional_bandwidth(port, value)
    step1 = convert(Int64, floor(value * 100[1]))
    step2 = string(step1, base = 16)
    cmd = "1d" * lpad(step2, 8, "0")
    str = write_controller(port, cmd)
    if ~isnothing(str)
        sign = (str[1:2] == "ff") ? :- : :+
        return decode_temperature(str, sign)
    else
        return missing
    end
end

"""
    read_integral_gain(port)

    Fixed-point gain in repeats/min
"""
function read_integral_gain(port)
    cmd = "52"
    str = "00000000"
    str = write_controller(port, cmd * str)
    if ~isnothing(str)
        return decode_temperature(str, :+)
    else
        return missing
    end
end

"""
    write_integral_gain(port, value)

    Fixed-point gain in repeats/min
"""
function write_integral_gain(port, value)
    step1 = convert(Int64, floor(value * 100[1]))
    step2 = string(step1, base = 16)
    cmd = "1e" * lpad(step2, 8, "0")
    str = write_controller(port, cmd)
    if ~isnothing(str)
        return decode_temperature(str, :+)
    else
        return missing
    end
end

"""
    read_derivative_gain(port)

    Fixed-point gain in min
"""
function read_derivative_gain(port)
    cmd = "53"
    str = "00000000"
    str = write_controller(port, cmd * str)
    if ~isnothing(str)
        return decode_temperature(str, :+)
    else
        return missing
    end
end

"""
    write_derivative_gain(port, value)

    Fixed-point gain in min
"""
function write_derivative_gain(port, value)
    step1 = convert(Int64, floor(value * 100[1]))
    step2 = string(step1, base = 16)
    cmd = "1f" * lpad(step2, 8, "0")
    str = write_controller(port, cmd)
    if ~isnothing(str)
        return decode_temperature(str, :+)
    else
        return missing
    end
end

end
