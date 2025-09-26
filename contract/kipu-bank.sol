// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title KipuBank
/// @author regenn
/// @notice Permite que usuarios depositen ETH en una bóveda personal y retiren hasta un límite por transacción.
/// @notice Permite el deposito y retiro de ETH hasta el limite de transaccion.

contract KipuBank {
    /*///////////////////////////////////////////////////////////////
                                ERRORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Revert cuando el deposito excede la capacidad total del banco.
    /// @param total Suma de activos totales actuales más el depósito solicitado.
    /// @param bankCap Valor máximo de activos permitidos.
    error ErrExcedeBankCap(uint256 total, uint256 bankCap);

    /// @notice Revert cuando se intenta depositar 0 ETH.
    error ErrDepositaCero();

    /// @notice Revert cuando se intenta retirar 0 ETH.
    error ErrRetiraCero();

    /// @notice Revert cuando el usuario intenta retirar más que su balance.
    /// @param balanceDisponible Balance disponible del usuario.
    /// @param montoSolicitado Monto solicitado a retirar.
    error ErrSaldoInsuficiente(uint256 balanceDisponible, uint256 montoSolicitado);

    /// @notice Revert cuando la cantidad solicitada excede el límite por transacción.
    /// @param monto Monto solicitado.
    /// @param limiteXTransaccion Límite por transacción inmutable.
    error ErrExcedeLimiteXTransaccion(uint256 monto, uint256 limiteXTransaccion);

    /// @notice Revert cuando la transferencia nativa falla.
    /// @param addr_destino Dirección destino.
    /// @param monto Monto intentado enviar.
    error ErrTransferenciaFallida(address addr_destino, uint256 monto);

    /*///////////////////////////////////////////////////////////////
                             CONSTANTES / INMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Límite por transacción para retiros. Se configura en deploy y es inmutable.
    uint256 public immutable limiteRetiroXTransaccion;

    /// @notice Límite global de activos mantenidos por el banco. Se establece en el constructor.
    uint256 public immutable bankCap;

    /// @notice Versión del contrato.
    string public constant VERSION = "KipuBank v1";

    /*///////////////////////////////////////////////////////////////
                             VARIABLES DE ESTADO
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping que guarda el saldo por cada usuario.
    mapping(address => uint256) private saldo;

    /// @notice Contador global de depósitos exitosos.
    uint256 private contDeposito;

    /// @notice Contador global de retiros exitosos.
    uint256 private contRetiro;

    /// @notice Contadores por usuario (depósitos y retiros).
    mapping(address => uint256) private depositosPorUsuario;
    mapping(address => uint256) private retirosPorUsuario;

    /// @notice Activos totales actualmente retenidos por el contrato (suma de todos los balances).
    uint256 private totalBalances;

    /*///////////////////////////////////////////////////////////////
                                  EVENTOS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitido cuando un usuario deposita ETH.
    /// @param user Dirección que depositó.
    /// @param monto Monto depositado.
    /// @param nuevoSaldo Nuevo balance del usuario luego del depósito.
    event Depositar(address indexed user, uint256 monto, uint256 nuevoSaldo);

    /// @notice Emitido cuando un usuario retira ETH.
    /// @param user Dirección que retiró.
    /// @param monto Monto retirado.
    /// @param nuevoSaldo Nuevo balance del usuario luego del retiro.
    event Retirar(address indexed user, uint256 monto, uint256 nuevoSaldo);

    /*///////////////////////////////////////////////////////////////
                                 MODIFICADORES
    //////////////////////////////////////////////////////////////*/

    /// @notice Valida que el depósito no haga que el total de activos exceda `bankCap`.
    /// @param monto Monto del depósito.
    modifier NoExcedeBankCap(uint256 monto) {
        uint256 total = totalBalances + monto;
        if (total > bankCap) revert ErrExcedeBankCap(total, bankCap);
        _;
    }

    /// @notice Valida que un valor sea mayor que cero.
    /// @param monto Valor a validar.
    modifier mayorACero(uint256 monto) {
        if (monto == 0) revert ErrDepositaCero();
        _;
    }

    /*///////////////////////////////////////////////////////////////
                                 CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Crea el contrato KipuBank.
    /// @param _bankCap Capacidad máxima total de ETH que el banco puede retener.
    /// @param _limiteRetiroXTransaccion Límite máximo por retiro en una transacción.
    constructor(uint256 _bankCap, uint256 _limiteRetiroXTransaccion) {
        require(_bankCap > 0, "bankCap debe ser > 0"); // inicial check de argumentos (strings permitidos en constructor)
        require(_limiteRetiroXTransaccion > 0, "limiteRetiroXTransaccion debe ser > 0");
        bankCap = _bankCap;
        limiteRetiroXTransaccion = _limiteRetiroXTransaccion;
    }

    /*///////////////////////////////////////////////////////////////
                             FUNCIÓN EXTERNAL PAYABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Deposita ETH en la bóveda del remitente.
    /// Emite un {Deposit} event.
    function deposita() external payable NoExcedeBankCap(msg.value) {
        if (msg.value== 0) revert ErrDepositaCero();

        saldo[msg.sender] += msg.value;
        totalBalances += msg.value;

        // contadores
        contDeposito += 1;
        depositosPorUsuario[msg.sender] += 1;

        // emite evento
        emit Depositar(msg.sender, msg.value, saldo[msg.sender]);
    }

    /// @notice Recibir ETH sin calldata: lo redirigimos a deposit().
    receive() external payable {
        // se valida bankCap manualmente porque modifiers no aplican al receive.
        if (msg.value == 0) revert ErrDepositaCero();
        uint256 total = totalBalances + msg.value;
        if (total > bankCap) revert ErrExcedeBankCap(total, bankCap);

        saldo[msg.sender] += msg.value;
        totalBalances += msg.value;

        contDeposito += 1;
        depositosPorUsuario[msg.sender] += 1;

        emit Depositar(msg.sender, msg.value, saldo[msg.sender]);
    }

    /*///////////////////////////////////////////////////////////////
                             FUNCIÓN EXTERNAL (Retiros)
    //////////////////////////////////////////////////////////////*/

    /// @notice Retira `monto` ETH desde tu bóveda, hasta `limiteRetiroXTransaccion`.
    /// @param monto Cantidad a retirar (en wei).
    /// @dev Aplica checks-effects-interactions: actualiza balances antes de transferir.
    /// Emits a {Withdraw} event.
    function Retira(uint256 monto) external {
        if (monto == 0) revert ErrRetiraCero();

        // Checks
        uint256 saldoUsuario = saldo[msg.sender];
        if (monto > saldoUsuario) revert ErrSaldoInsuficiente(saldoUsuario, monto);
        if (monto > limiteRetiroXTransaccion) revert ErrExcedeLimiteXTransaccion(monto, limiteRetiroXTransaccion);

        // Effects (actualizar estado antes de la interacción)
        saldo[msg.sender] = saldoUsuario - monto;
        totalBalances -= monto;

        contRetiro += 1;
        retirosPorUsuario[msg.sender] += 1;

        emit Retirar(msg.sender, monto, saldo[msg.sender]);

        // Interactions (transferir ETH de forma segura)
        _envioSeguro(msg.sender, monto);
    }

    /*///////////////////////////////////////////////////////////////
                             FUNCIÓN PRIVADA
    //////////////////////////////////////////////////////////////*/

    /// @notice Envía ETH de forma segura usando call y revert con error personalizado en fallo.
    /// @param addr_destino Dirección destino.
    /// @param monto Monto a enviar.
    function _envioSeguro(address addr_destino, uint256 monto) private {
        (bool ok, ) = addr_destino.call{value: monto}("");
        if (!ok) revert ErrTransferenciaFallida(addr_destino, monto);
    }

    /*///////////////////////////////////////////////////////////////
                             FUNCIONES VIEW / EXTERNAS
    //////////////////////////////////////////////////////////////*/

    /// @notice Obtiene el balance de la bóveda del usuario `addr_origen`.
    /// @param addr_origen Dirección cuya bóveda se consulta.
    /// @return saldo Balance en wei.
    function getSaldo(address addr_origen) external view returns (uint256) {
        return saldo[addr_origen];
    }

    /// @notice Total de activos retenidos por el banco (suma de todas las bóvedas).
    /// @return totalBalances_ en wei.
    function getTotalBalances() external view returns (uint256) {
        return totalBalances;
    }

    /// @notice Contador global de depósitos realizados en el contrato.
    /// @return contDeposito_ número de depósitos.
    function getContDeposito() external view returns (uint256) {
        return contDeposito;
    }

    /// @notice Contador global de retiros realizados en el contrato.
    /// @return contRetiro_ número de retiros.
    function getContRetiro() external view returns (uint256) {
        return contRetiro;
    }

    /// @notice Devuelve la cantidad de depósitos realizados por `user`.
    /// @param user Dirección a consultar.
    function getDepositosPorUsuario(address user) external view returns (uint256) {
        return depositosPorUsuario[user];
    }

    /// @notice Devuelve la cantidad de retiros realizados por `user`.
    /// @param user Dirección a consultar.
    function getRetirosPorUsuario(address user) external view returns (uint256) {
        return retirosPorUsuario[user];
    }

    /*///////////////////////////////////////////////////////////////
                             UTILIDADES
    //////////////////////////////////////////////////////////////*/

    /// @notice Fallback para evitar recibir calldata inesperada.
    fallback() external payable {
        if (msg.value == 0) return;

        uint256 total = totalBalances + msg.value;
        if (total > bankCap) revert ErrExcedeBankCap(total, bankCap);

        saldo[msg.sender] += msg.value;
        totalBalances += msg.value;

        contDeposito += 1;
        depositosPorUsuario[msg.sender] += 1;

        emit Depositar(msg.sender, msg.value, saldo[msg.sender]);
    }
}
