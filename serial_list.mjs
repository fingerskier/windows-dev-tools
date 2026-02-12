import { SerialPort } from 'serialport';

const ports = SerialPort.list();

ports.then(these => {
  these.forEach(port => {
    console.log(`${port.friendlyName} ${port.path} ${port.vendorId}x${port.productId}`)
  })
});
