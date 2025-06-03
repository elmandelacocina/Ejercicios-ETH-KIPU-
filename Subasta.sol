// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// Subasta Dinámica con Extensión y Reembolsos Parciales
/// Permite ofertar por un artículo, extendiendo el tiempo final con cada nueva oferta válida.

contract Subasta {
    /// @notice Dirección del dueño de la subasta
    address public immutable owner;

    ///  @notice Marca el inicio de la subasta (timestamp)
    uint256 public immutable inicioTiempo;

    /// @notice  Marca el final original de la subasta (timestamp)
    uint256 public immutable setTiempoFinal;

    /// @notice Marca el final actualizado de la subasta (timestamp)
    uint256 public tiempoActualizado;

    /// @notice Dirección del ofertante con la oferta más alta
    address public mayorOfertante;

    /// @notice Valor de la oferta más alta
    uint256 public mayorOferta;

    /// @notice Indica si la subasta ya fue finalizada
    bool public ended;

    /// @notice Comisión de reembolso: 2% para ofertantes no ganadores
    uint256 public constant comision = 200; // 2% en basis points (1% = 100bps)

    /// @notice Mapeo de las ofertas por dirección
    mapping(address => uint256) public bids;

    /// @notice Lista de ofertantes únicos
    address[] public ofertantes;

    /// @notice Evento emitido al realizar una nueva oferta válida
    event NuevaOferta(address indexed ofertante, uint256 amount, uint256 nuevotiempoActualizado);

    /// @notice Evento emitido al finalizar la subasta
    event SubastaFinalizada(address ganador, uint256 amount);

    /// @notice Modificador para restringir acceso al dueño
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el dueno puede ejecutar");
        _;
    }

    /// @notice Modificador para verificar si la subasta está activa
    modifier onlyWhileActive() {
        require(block.timestamp >= inicioTiempo, "Subasta no ha iniciado");
        require(block.timestamp <= tiempoActualizado, "Subasta finalizada");
        _;
    }

    /// @notice Modificador para una sola ejecución tras el fin de la subasta
    modifier onlyAfterEnd() {
        require(block.timestamp > tiempoActualizado, "Subasta aun activa");
        require(!ended, "Subasta ya finalizada");
        _;
    }

    /**
     * @notice Constructor de la subasta
     * @dev _duration: Duración en segundos desde el inicio hasta el fin inicial
     */
    constructor(uint256 _duration) {
        require(_duration > 0, "Duracion invalida"); // Valor siempre superior a 0
        owner = msg.sender;
        inicioTiempo = block.timestamp;
        setTiempoFinal = block.timestamp + _duration;
        tiempoActualizado = setTiempoFinal;
    }

    /**
     * @notice Realiza una oferta. La oferta debe superar la oferta más alta actual al menos en 5%.
     * @notice Si se realiza dentro de los últimos 10 minutos, extiende la subasta por 10 minutos.
     */
    function ofertar() external payable onlyWhileActive {
        require(msg.value > 0, "Debe enviar Ether"); // El valor siempre superior a 0
        uint256 currentBid = bids[msg.sender] + msg.value;
        uint256 minRequired = mayorOferta + (mayorOferta * 5) / 100; // Calcula el 5% de la ultima oferta

        // @notice Primera oferta siempre válida
        if (mayorOferta > 0) {
            require(currentBid >= minRequired, "Oferta debe superar en al menos 5%");
        }

        //@notice Nuevo ofertante
        if (bids[msg.sender] == 0) {
            ofertantes.push(msg.sender);
        }

        bids[msg.sender] = currentBid;

        mayorOferta = currentBid;
        mayorOfertante = msg.sender;

        //@notice Extensión dinámica si estamos a menos de 10 minutos del final
        if (block.timestamp >= tiempoActualizado - 10 minutes) {
            tiempoActualizado = block.timestamp + 10 minutes;
        }

        emit NuevaOferta(msg.sender, currentBid, tiempoActualizado); // emite el evento
    }

       /**
    * @notice Permite retirar parte del exceso de depósito durante la subasta.
    * @param amount: Monto a retirar (debe ser menor o igual al total depositado)
    */
    function retirarExcedente(uint256 amount) external onlyWhileActive {
        uint256 bidAmount = bids[msg.sender];
        require(bidAmount > 0, "No hay fondos depositados");
        require(msg.sender != mayorOfertante, "Ganador no puede retirar");
        require(amount > 0 && amount <= bidAmount, "Monto invalido");

    // @notice Reducimos el deposito del usuario
    bids[msg.sender] = bidAmount - amount;

    // @notice Transferimos la cantidad solicitada
    // usamos este metodo para evitar el uso de send o transfer
    (bool sent, ) = msg.sender.call{value: amount}("");
    require(sent, "Fallo en el retiro");
    }

    /**
     *  Finaliza la subasta y permite el retiro de depósitos no ganadores con comisión del 2%.
     */
    function finalizarSubasta() external onlyAfterEnd {
        ended = true;

        emit SubastaFinalizada(mayorOfertante, mayorOferta); // emite el evento
    }

    /**
     *  @notice Permite a ofertantes no ganadores retirar su depósito con un 2% de comisión.
     */
    function retirarDeposito() external {
        require(ended, "Subasta no ha finalizado");
        require(msg.sender != mayorOfertante, "Ganador no puede retirar aqui");

        uint256 amount = bids[msg.sender];
        require(amount > 0, "Nada que retirar");

        bids[msg.sender] = 0;

        uint256 fee = (amount * comision) / 10000;
        uint256 refund = amount - fee;

        (bool sent, ) = msg.sender.call{value: refund}("");
        require(sent, "Fallo en el reembolso");
    }

    /**
     *  @notice Retorna la lista de todos los ofertantes y sus ofertas.
     *  @return addresses Array de direcciones de los ofertantes.
     *  @return amounts Array de montos ofertados por cada dirección.
     */
    function mostrarOfertas() external view returns (address[] memory addresses, uint256[] memory amounts) {
        uint256 len = ofertantes.length;
        addresses = new address[](len);
        amounts = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            address ofertante = ofertantes[i];
            addresses[i] = ofertante;
            amounts[i] = bids[ofertante];
        }
    }

    /**
     *  @notice Retorna el ganador actual y la oferta ganadora
     *  @return ganador Dirección del ofertante con la oferta más alta
     *  @return oferta Monto de la oferta más alta
     */
    function mostrarGanador() external view returns (address ganador, uint256 oferta) {
        return (mayorOfertante, mayorOferta);
    }

 /**
     * @notice Retorna el número de ofertantes únicos
     * @return count Número de participantes únicos
     */
    function numeroDeOfertantes() external view returns (uint256) {
        return ofertantes.length;
    }

   /**
     * @dev Rechaza depósitos directos a menos que sea mediante la función ofertar().
     */
    fallback() external payable {
        revert("Usa ofertar()"); // Siempre usar Ofertar para poder controlar mejor
    }

    receive() external payable {
        revert("Usa ofertar()"); // Siempre usar Ofertar para poder controlar mejor
    }
}
